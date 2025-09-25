import Foundation
import Combine
import UserNotifications
import StoreKit

enum EnrollmentError: LocalizedError {
    case alreadyInProgress
    
    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "Enrollment already in progress for this invitation"
        }
    }
}

final class AppStore: ObservableObject {
    enum AppPhase: Equatable {
        case launching
        case onboarding
        case enrollmentPending(EnrollmentContext)
        case registered
    }

    // Public app state
    @Published var appPhase: AppPhase = .launching
    @Published var pushToken: String?
    @Published private(set) var model: DomainModel = .empty
    @Published var upcoming: [Dienst] = []
    @Published var searchResults: [SearchTeam] = []
    @Published var onboardingScan: ScannedTenant?
    @Published var pendingCTA: CTA?
    @Published var leaderboards: [String: LeaderboardData] = [:]  // tenantSlug -> LeaderboardData
    @Published var leaderboardErrors: [String: String] = [:]  // tenantSlug -> error message
    @Published var globalLeaderboard: GlobalLeaderboardData?
    @Published var tenantInfo: [String: TenantInfo] = [:] // tenantSlug -> TenantInfo (club logos etc.)
    @Published var banners: [String: [DomainModel.Banner]] = [:] // tenantSlug -> [Banner] (cached banner data)
    
    // Network connectivity
    @Published var isOnline: Bool = true
    let networkMonitor = NetworkMonitor.shared
    
    // Reactive push navigation state
    private var pendingPushNavigation: (tenant: String, team: String)?
    private var pushNavigationCancellable: AnyCancellable?

    // Services
    private let enrollmentRepository: EnrollmentRepository
    private let dienstRepository: DienstRepository
    private let pushService: PushService
    private let leaderboardRepository: LeaderboardRepository

    private var cancellables: Set<AnyCancellable> = []
    
    // Duplicate enrollment prevention
    private var pendingEnrollmentTokens: Set<String> = []
    private var usedEnrollmentTokens: Set<String> = []
    private var isRegisteringMember: Bool = false

    init(
        enrollmentRepository: EnrollmentRepository = DefaultEnrollmentRepository(),
        dienstRepository: DienstRepository = DefaultDienstRepository(),
        pushService: PushService = DefaultPushService(),
        leaderboardRepository: LeaderboardRepository = DefaultLeaderboardRepository()
    ) {
        self.enrollmentRepository = enrollmentRepository
        self.dienstRepository = dienstRepository
        self.pushService = pushService
        self.leaderboardRepository = leaderboardRepository

        // Bootstrap
        Logger.section("APP BOOTSTRAP")
        Logger.bootstrap("Initializing AppStore with repositories")
        Logger.bootstrap("Build configuration: \(Logger.buildInfo)")
        Logger.bootstrap("Logging enabled: \(Logger.isLoggingEnabled)")
        
        // Initialize error handler
        _ = ErrorHandler.shared
        
        // Setup network monitoring
        setupNetworkMonitoring()
        
        self.model = enrollmentRepository.loadModel()
        Logger.bootstrap("Loaded domain model: \(model.tenants.count) tenants")
        
        self.appPhase = model.isEnrolled ? .registered : .onboarding
        Logger.bootstrap("App phase: \(appPhase)")
        
        // No cache system - using direct data model as single source of truth
        Logger.bootstrap("Using data-driven architecture")
        
        // Listen for token revocation notifications from repositories
        NotificationCenter.default.addObserver(
            forName: .tokenRevoked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let tenant = notification.userInfo?["tenant"] as? String,
                  let reason = notification.userInfo?["reason"] as? String else { return }
            
            Logger.auth("📢 Received token revocation notification for tenant \(tenant)")
            self?.handleTokenRevocation(for: tenant, reason: reason)
        }
        
        if model.isEnrolled { 
            Logger.bootstrap("User enrolled - refreshing diensten")
            refreshDiensten() 
        } else {
            Logger.bootstrap("User not enrolled - showing onboarding")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pushNavigationCancellable?.cancel()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                Logger.network("Network state: \(isConnected ? "Online" : "Offline")")
                
                if !isConnected {
                    Logger.warning("App is offline - some features will be disabled")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Intent
    func handleIncomingURL(_ url: URL) {
        if DeepLink.isEnrollment(url) { handleEnrollmentDeepLink(url) }
        else if DeepLink.isCTA(url) { handleCTALink(url) }
        else if DeepLink.isInvite(url) { handleInviteLink(url) }
    }
    
    // MARK: - Reactive Push Navigation
    private func triggerReactivePushNavigation(tenant: String, team: String) {
        // Cancel any previous pending navigation
        pushNavigationCancellable?.cancel()
        
        // Store navigation request
        pendingPushNavigation = (tenant: tenant, team: team)
        Logger.push("🎯 Reactive navigation queued for tenant='\(tenant)' team='\(team)'")
        
        // Start data refresh immediately (non-blocking)
        Logger.push("🔄 Starting data refresh for push navigation")
        refreshDiensten()
        
        // Create reactive publisher that waits for fresh data OR timeout
        pushNavigationCancellable = $upcoming
            .dropFirst() // Skip current stale value
            .timeout(.seconds(2.0), scheduler: DispatchQueue.main) // Max 2s wait
            .sink(
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        Logger.push("⏱️ Reactive navigation finished waiting - proceeding (no error)")
                        self?.executePendingNavigation()
                    case .failure:
                        Logger.push("⏰ Reactive navigation timeout - proceeding with cached data")
                        self?.executePendingNavigation()
                    }
                },
                receiveValue: { [weak self] diensten in
                    Logger.push("📊 Fresh data received (\(diensten.count) diensten) - executing navigation")
                    self?.executePendingNavigation()
                }
            )
    }
    
    private func executePendingNavigation() {
        guard let navigation = pendingPushNavigation else {
            Logger.push("🚫 No pending navigation to execute")
            return
        }
        
        // Clear pending state
        pendingPushNavigation = nil
        pushNavigationCancellable?.cancel()
        
        // Final safety check
        guard appPhase == .registered else {
            Logger.push("🚫 Navigation cancelled - app not in registered state")
            return
        }
        
        Logger.push("🚀 Executing push navigation to tenant='\(navigation.tenant)' team='\(navigation.team)'")
        
        NotificationCenter.default.post(
            name: .pushNavigationRequested,
            object: nil,
            userInfo: [
                "tenant": navigation.tenant,
                "team": navigation.team,
                "source": "push_notification"
            ]
        )
    }

    func setPushToken(_ token: String) { 
        self.pushToken = token
        // Register APNs token once with any available enrollment token
        // Backend will update all enrollments for this device
        if let anyAuthToken = model.primaryAuthToken {
            Logger.push("🔔 Registering APNs token with backend using available auth token")
            pushService.updateAPNs(token: token, auth: anyAuthToken)
        } else {
            Logger.push("⚠️ No auth tokens available for APNs registration - will retry after enrollment")
            // Store the token and try again shortly in case enrollment is in progress
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.pushToken == token else { return }
                if let anyAuthToken = self.model.primaryAuthToken {
                    Logger.push("🔄 Retrying APNs token registration after delay")
                    self.pushService.updateAPNs(token: token, auth: anyAuthToken)
                }
            }
        }
    }
    func handlePushRegistrationFailure(_ error: Error) { Logger.error("APNs failure: \(error)") }
    func handleNotification(userInfo: [AnyHashable: Any]) {
        // CRITICAL: Only handle navigation when app is in registered state
        // Prevents navigation during onboarding/enrollment flows
        guard appPhase == .registered else {
            Logger.push("🚫 Push navigation ignored - app not registered (phase: \(appPhase))")
            return
        }
        
        // Extract navigation metadata with strict validation
        guard let tenantSlug = userInfo["tenant_slug"] as? String,
              !tenantSlug.isEmpty,
              let teamCode = userInfo["team_code"] as? String,
              !teamCode.isEmpty else {
            Logger.push("🚫 Push navigation ignored - missing or invalid navigation data")
            Logger.push("   tenant_slug: \(userInfo["tenant_slug"] ?? "nil")")
            Logger.push("   team_code: \(userInfo["team_code"] ?? "nil")")
            return
        }
        
        // Validate user has access to the requested tenant
        guard model.tenants[tenantSlug] != nil else {
            Logger.push("🚫 Push navigation denied - no access to tenant: '\(tenantSlug)'")
            Logger.push("   Available tenants: \(Array(model.tenants.keys))")
            return
        }
        
        // Additional safety: Validate team exists within tenant
        if let tenant = model.tenants[tenantSlug] {
            let hasTeamAccess = tenant.teams.contains { team in
                team.id == teamCode || team.code == teamCode
            }
            
            if !hasTeamAccess {
                Logger.push("🚫 Push navigation denied - no access to team '\(teamCode)' in tenant '\(tenantSlug)'")
                Logger.push("   Available teams: \(tenant.teams.map { "id=\($0.id) code=\($0.code ?? "nil")" })")
                return
            }
        }
        
        Logger.push("✅ Push navigation approved: tenant='\(tenantSlug)' team='\(teamCode)'")
        
        // Use reactive navigation that waits for fresh data
        triggerReactivePushNavigation(tenant: tenantSlug, team: teamCode)
    }

    func configurePushNotifications() {
        pushService.requestAuthorization()
    }

    func startNewEnrollment() { 
        Logger.enrollment("Starting fresh enrollment flow")
        // Clear all onboarding state for clean start
        onboardingScan = nil
        searchResults = []
        appPhase = .onboarding
        Logger.enrollment("Onboarding state cleared")
    }
    func resetAll() {
        Logger.info("Starting full app reset...")
        Logger.debug("Current model has \(model.tenants.count) tenants")
        
        // Call backend to remove all enrollments using any available token
        if let anyToken = model.primaryAuthToken {
            Logger.network("Calling backend removeAllEnrollments with token: \(anyToken.prefix(20))...")
            enrollmentRepository.removeAllEnrollments { [weak self] result in
                Logger.network("Backend removeAll completed with result: \(result)")
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        Logger.success("Backend reset successful")
                    case .failure(let error):
                        Logger.error("Backend reset failed: \(error)")
                    }
                    // Always clear local state regardless
                    self?.clearLocalState()
                }
            }
        } else {
            Logger.warning("No auth token for backend reset, clearing local only")
            clearLocalState()
        }
    }
    
    
    private func clearLocalState() {
        Logger.debug("Clearing local state...")
        Logger.debug("Before clear: \(model.tenants.count) tenants, \(upcoming.count) diensten")
        
        // Clear local state (auth tokens are now handled per-operation)
        
        model = .empty
        upcoming = []
        searchResults = []
        onboardingScan = nil
        pushToken = nil
        Logger.debug("After clear: \(model.tenants.count) tenants, \(upcoming.count) diensten")
        Logger.debug("Setting appPhase to .onboarding")
        appPhase = .onboarding
        enrollmentRepository.persist(model: model)
        Logger.success("Local reset complete - should now see onboarding")
    }

    // QR handling: a simplified representation of scanned tenant
    struct ScannedTenant { let slug: TenantID; let name: String }
    func handleQRScan(slug: TenantID, name: String) { onboardingScan = ScannedTenant(slug: slug, name: name) }

    enum CTA: Equatable { case shiftVolunteer(token: String) }

    func submitEmail(_ email: String, for tenant: TenantID, selectedTeamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        // Old flow: if no team codes yet, first fetch allowed teams for selection
        if selectedTeamCodes.isEmpty {
            Logger.enrollment("🔎 fetching allowed teams for email=\(email) tenant=\(tenant)")
            enrollmentRepository.fetchAllowedTeams(email: email, tenant: tenant) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let teams):
                        Logger.enrollment("✅ allowed teams count=\(teams.count)")
                        // In a full flow, we would present team selection here.
                        // For now, keep state for UI to show selection in onboarding.
                        self?.searchResults = teams
                        completion(.success(()))
                    case .failure(let err):
                        Logger.enrollment("❌ fetch allowed teams: \(err)")
                        completion(.failure(err))
                    }
                }
            }
        } else {
            enrollmentRepository.requestEnrollment(email: email, tenant: tenant, teamCodes: selectedTeamCodes) { [weak self] result in
                switch result {
                case .success:
                    DispatchQueue.main.async { self?.appPhase = .enrollmentPending(EnrollmentContext(tenant: tenant, issuedAt: Date())); completion(.success(())) }
                case .failure(let err): 
                    let translated = ErrorTranslations.translate(err)
                    completion(.failure(NSError(domain: "AppStore", code: -1, userInfo: [NSLocalizedDescriptionKey: translated])))
                }
            }
        }
    }

    func completeEnrollment(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we're already processing this exact token
        if pendingEnrollmentTokens.contains(token) {
            Logger.warning("⚠️ Enrollment already in progress for token: \(token.prefix(10))...")
            completion(.failure(EnrollmentError.alreadyInProgress))
            return
        }
        
        // Check if this token was already used successfully
        if usedEnrollmentTokens.contains(token) {
            Logger.warning("⚠️ Enrollment token already used: \(token.prefix(10))...")
            completion(.failure(EnrollmentError.alreadyInProgress))
            return
        }
        
        // Mark token as pending
        pendingEnrollmentTokens.insert(token)
        Logger.auth("🔄 Starting enrollment with token: \(token.prefix(10))...")
        
        enrollmentRepository.registerDevice(enrollmentToken: token, pushToken: pushToken) { [weak self] result in
            guard let self = self else { return }
            
            // Always clean up pending token
            self.pendingEnrollmentTokens.remove(token)
            
            switch result {
            case .success(let delta):
                DispatchQueue.main.async {
                    Logger.success("✅ Enrollment completed for token: \(token.prefix(10))...")
                    
                    // Mark token as successfully used to prevent reuse
                    self.usedEnrollmentTokens.insert(token)
                    
                    // Merge with dedup and role precedence
                    var next = self.model
                    // Remove overlapping team IDs in same tenant when new role is manager
                    if let existing = next.tenants[delta.tenant.slug], delta.teams.contains(where: { $0.role == .manager }) {
                        let incomingIds = Set(delta.teams.map { $0.id })
                        var modified = existing
                        modified.teams.removeAll { incomingIds.contains($0.id) }
                        next.tenants[existing.slug] = modified
                    }
                    // Enforce max 5 total teams
                    let existingCount = next.tenants.values.reduce(0) { $0 + $1.teams.count }
                    let availableSlots = max(0, 5 - existingCount)
                    let trimmedTeams = Array(delta.teams.prefix(availableSlots))
                    let trimmedDelta = EnrollmentDelta(tenant: delta.tenant, teams: trimmedTeams, signedDeviceToken: delta.signedDeviceToken)
                    next = next.applying(delta: trimmedDelta)
                    self.model = next
                    self.enrollmentRepository.persist(model: self.model)
                    self.appPhase = .registered
                    self.refreshDiensten()
                    
                    // CRITICAL: Ensure push notifications are configured immediately after enrollment
                    self.configurePushNotifications()
                    
                    // Register push token with backend (once, using any available auth token)
                    if let token = self.pushToken, let anyAuthToken = self.model.primaryAuthToken {
                        Logger.push("Re-registering APNs token after enrollment completion")
                        self.pushService.updateAPNs(token: token, auth: anyAuthToken)
                    } else {
                        Logger.push("⏳ Push token will be registered when received from iOS")
                    }
                    completion(.success(()))
                }
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    // MARK: - Shared Tenant Cleanup
    private func cleanupTenantData(_ tenant: TenantID) {
        Logger.debug("🧹 Cleaning up all data for tenant: \(tenant)")
        
        // Remove tenant from model
        model.tenants.removeValue(forKey: tenant)
        
        // Clean up ALL related data for this tenant
        upcoming.removeAll { $0.tenantId == tenant }
        tenantInfo.removeValue(forKey: tenant)
        leaderboards.removeValue(forKey: tenant)
        
        // Clear global leaderboard cache to prevent stale highlighting
        globalLeaderboard = nil
        
        // Persist changes
        enrollmentRepository.persist(model: model)
        
        Logger.success("Tenant data cleanup complete for: \(tenant)")
    }
    
    func removeTenant(_ tenant: TenantID) {
        Logger.debug("🗑️ Removing tenant: \(tenant)")
        
        // Get the specific tenant's token before removing it from the model
        let tenantToken = model.tenants[tenant]?.signedDeviceToken
        Logger.debug("Tenant-specific auth token available: \(tenantToken != nil)")
        
        // Perform all local cleanup
        cleanupTenantData(tenant)
        
        // Try backend removal if we have the tenant's auth token
        if let token = tenantToken {
            // Create a temporary backend client with the specific tenant's token
            let tempBackend = BackendClient()
            tempBackend.authToken = token
            Logger.auth("Using tenant-specific token for removal")
            
            tempBackend.removeTenant(tenant) { result in
                Logger.network("Backend tenant removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            Logger.warning("No tenant-specific auth token - member enrollment, local removal only")
        }
    }

    func removeTeam(_ team: TeamID, from tenant: TenantID) {
        Logger.debug("🗑️ Removing team: \(team) from tenant: \(tenant)")
        
        // Get the specific token for this team/tenant before removing it from the model
        let authToken = model.authTokenForTeam(team, in: tenant)
        Logger.debug("Team-specific auth token available: \(authToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTeam(team, from: tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        Logger.success("Local team removal complete")
        
        // Try backend removal if we have the team's auth token
        if let token = authToken {
            // Create a temporary backend client with the specific token
            let tempBackend = BackendClient()
            tempBackend.authToken = token
            Logger.auth("Using enrollment-specific token for team removal")
            
            tempBackend.removeTeams([team]) { [weak self] result in
                Logger.network("Backend team removal result: \(result)")
                // Local state already updated, so no need to update again
                if case .failure(let error) = result {
                    self?.handlePotentialTokenRevocation(error: error, tenant: tenant)
                }
            }
        } else {
            Logger.warning("No enrollment-specific auth token - member enrollment, local removal only")
        }
    }
    
    // MARK: - Token Revocation Handling
    
    func handleTokenRevocation(for tenant: TenantID, reason: String?) {
        Logger.auth("🚨 Token revoked for tenant \(tenant), reason: \(reason ?? "unknown")")
        
        guard var tenantData = model.tenants[tenant] else {
            Logger.warning("Tenant \(tenant) not found when handling revocation")
            return
        }
        
        // Mark tenant as season ended and invalidate its token
        tenantData.seasonEnded = true
        tenantData.signedDeviceToken = nil  // Clear the revoked token
        model.tenants[tenant] = tenantData
        
        // Mark enrollments as revoked but keep them for season summary access
        let tenantEnrollmentIds = tenantData.enrollments
        for enrollmentId in tenantEnrollmentIds {
            if let enrollment = model.enrollments[enrollmentId] {
                // Keep enrollment but mark as revoked by clearing token (this prevents API calls)
                // The enrollment data itself is preserved for season summary team selection
                Logger.auth("📋 Preserving enrollment \(enrollmentId) for season summary (token will be cleared for \(enrollment.teams.count) teams)")
            }
        }
        // Note: Keep tenantData.enrollments intact for season summary team selection
        
        // Persist the updated model
        enrollmentRepository.persist(model: model)
        
        Logger.auth("✅ Tenant \(tenant) marked as season ended and tokens cleared")
        
        // Refresh data to update UI (will skip season-ended tenant)
        refreshDiensten()
    }
    
    private func handlePotentialTokenRevocation(error: Error, tenant: TenantID) {
        // Check if error indicates token revocation
        if let nsError = error as NSError?, 
           nsError.domain == "BackendTokenError",
           let errorType = nsError.userInfo["errorType"] as? String {
            
            switch errorType {
            case "token_revoked":
                let reason = nsError.userInfo["reason"] as? String
                handleTokenRevocation(for: tenant, reason: reason)
            case "invalid_token":
                Logger.auth("Invalid token for tenant \(tenant) - may need re-enrollment")
                // Could also trigger re-enrollment flow in future
            default:
                Logger.debug("Other auth error for tenant \(tenant): \(errorType)")
            }
        }
    }
    
    func removeSeasonEndedTenant(_ tenantSlug: TenantID) {
        Logger.userInteraction("Remove Season Ended Tenant", target: "AppStore", context: ["tenant": tenantSlug])
        
        // Use shared cleanup function
        cleanupTenantData(tenantSlug)
        
        Logger.auth("Removed tenant \(tenantSlug) after season end")
        
        // Navigate appropriately
        if model.tenants.isEmpty {
            // No tenants left -> go to onboarding
            appPhase = .onboarding
            Logger.bootstrap("No tenants remaining - returning to onboarding")
        }
    }
    
    // MARK: - Data Refresh

    func refreshDiensten() {
        guard model.isEnrolled else { return }
        
        let startTime = Date()
        Logger.section("REFRESH DIENSTEN")
        Logger.debug("Refreshing diensten for \(model.tenants.count) tenants")
        
        for (slug, tenant) in model.tenants {
            Logger.debug("  → tenant \(slug): \(tenant.teams.count) teams")
        }
        
        // Fetch tenant info for club logos (background fetch)
        refreshTenantInfo()
        
        // Fetch banners for active tenants (background fetch, fail-safe)
        refreshBanners()
        
        // Fetch diensten using enrollment-specific tokens (handled in repository)
        dienstRepository.fetchUpcoming(for: model) { [weak self] result in
            DispatchQueue.main.async {
                let duration = Date().timeIntervalSince(startTime)
                if case .success(let items) = result { 
                    Logger.success("Received \(items.count) diensten")
                    Logger.performanceMeasure("Refresh Diensten", duration: duration, additionalInfo: "\(items.count) items")
                    self?.upcoming = items 
                } else {
                    Logger.performanceMeasure("Refresh Diensten (Failed)", duration: duration)
                }
            }
        }
    }
    
    func refreshBannersForTenant(_ tenantSlug: String) {
        // Only fetch banners for active (non-season ended) tenants
        guard let tenant = model.tenants[tenantSlug], !tenant.seasonEnded else {
            Logger.debug("Tenant \(tenantSlug) is season ended - skipping banner fetch")
            return
        }
        
        // Don't refetch if we already have banners cached for this tenant
        if banners[tenantSlug] != nil {
            Logger.debug("Banners already cached for tenant \(tenantSlug)")
            return
        }
        
        // Get tenant-specific auth token
        guard let authToken = model.authTokenForTeam(tenant.teams.first?.id ?? "", in: tenantSlug) else {
            Logger.warning("No auth token for tenant \(tenantSlug) - skipping banner fetch")
            return
        }
        
        Logger.debug("Fetching banners for tenant \(tenantSlug)")
        
        let backend = BackendClient()
        backend.authToken = authToken
        
        backend.fetchBanners(tenant: tenantSlug) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let bannerDTOs):
                    Logger.success("Received \(bannerDTOs.count) banners for tenant \(tenantSlug)")
                    
                    // Convert DTOs to domain models and sort by display order
                    let banners = bannerDTOs.map { dto in
                        DomainModel.Banner(
                            id: dto.id,
                            tenantSlug: dto.tenantSlug,
                            name: dto.name,
                            fileUrl: dto.fileUrl,
                            linkUrl: dto.linkUrl,
                            altText: dto.altText,
                            displayOrder: dto.displayOrder
                        )
                    }.sorted { $0.displayOrder < $1.displayOrder }
                    
                    // Cache the banners for this specific tenant
                    self?.banners[tenantSlug] = banners
                    Logger.success("Cached \(banners.count) banners for tenant \(tenantSlug)")
                    
                case .failure(let error):
                    Logger.warning("Failed to fetch banners for tenant \(tenantSlug): \(error.localizedDescription)")
                    // Don't crash the app - banners are non-critical
                    // Set empty array to prevent repeated fetch attempts
                    self?.banners[tenantSlug] = []
                }
            }
        }
    }
    
    // Legacy method for backward compatibility - now triggers on-demand loading
    func refreshBanners() {
        // This method is called from refreshDiensten() but we'll use lazy loading instead
        Logger.debug("Banner refresh triggered - will use on-demand loading per tenant")
    }
    
    func refreshTenantInfo() {
        // Get ALL tenants with tokens (not just active ones) to ensure club logos load for new enrollments
        let availableTenants = model.tenants.values.filter { tenant in
            // Check if we have any auth token for this tenant
            if let firstTeam = tenant.teams.first {
                return model.authTokenForTeam(firstTeam.id, in: tenant.slug) != nil
            }
            return false
        }
        
        guard !availableTenants.isEmpty,
              let firstTenant = availableTenants.first,
              let authToken = model.authTokenForTeam(firstTenant.teams.first?.id ?? "", in: firstTenant.slug) else {
            Logger.warning("No tenants with auth tokens available for tenant info")
            return
        }
        
        let backend = BackendClient()
        backend.authToken = authToken
        
        Logger.debug("Fetching tenant info using token from tenant \(firstTenant.slug)")
        
        backend.fetchTenantInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    Logger.success("Received tenant info for \(response.tenants.count) tenants")
                    self?.updateTenantInfoFromResponse(response)
                    
                case .failure(let error):
                    Logger.error("Failed to fetch tenant info: \(error)")
                    // Check if this is a token revocation for the specific tenant we used
                    self?.handlePotentialTokenRevocation(error: error, tenant: firstTenant.slug)
                }
            }
        }
    }
    
    private func updateTenantInfoFromResponse(_ response: TenantInfoResponse) {
        // Start with existing tenant info to preserve data for season-ended tenants
        var newTenantInfo: [String: TenantInfo] = tenantInfo
        
        for tenantData in response.tenants {
            let teams = tenantData.teams.map { teamData in
                TenantInfo.TeamInfo(
                    id: teamData.id,
                    code: teamData.code,
                    name: teamData.name,
                    role: teamData.role
                )
            }
            
            newTenantInfo[tenantData.slug] = TenantInfo(
                slug: tenantData.slug,
                name: tenantData.name,
                clubLogoUrl: tenantData.clubLogoUrl,
                seasonEnded: tenantData.seasonEnded,
                teams: teams
            )
            
            // Update domain model with latest tenant info (including logo URL and team names)
            if var existingTenant = model.tenants[tenantData.slug] {
                // Always update logo URL when available
                if let logoUrl = tenantData.clubLogoUrl {
                    existingTenant.clubLogoUrl = logoUrl
                }
                
                // CRITICAL: Update team names from tenant info (fix team codes showing as names)
                for i in 0..<existingTenant.teams.count {
                    let existingTeam = existingTenant.teams[i]
                    // Find matching team in tenant info by ID or code
                    if let tenantTeam = tenantData.teams.first(where: { 
                        $0.id == existingTeam.id || $0.code == existingTeam.code || $0.code == existingTeam.id 
                    }) {
                        Logger.debug("🔄 Updating team name: '\(existingTeam.name)' → '\(tenantTeam.name)' for id='\(existingTeam.id)'")
                        existingTenant.teams[i] = DomainModel.Team(
                            id: existingTeam.id,
                            code: tenantTeam.code,
                            name: tenantTeam.name, // Use correct name from tenant info
                            role: existingTeam.role,
                            email: existingTeam.email,
                            enrolledAt: existingTeam.enrolledAt
                        )
                    }
                }
                
                model.tenants[tenantData.slug] = existingTenant
                
                // Persist team name updates
                enrollmentRepository.persist(model: model)
                
                // CRITICAL: If tenant is season ended, update our domain model
                if tenantData.seasonEnded && !existingTenant.seasonEnded {
                    Logger.auth("🔄 Tenant \(tenantData.slug) detected as season ended from API")
                    existingTenant.seasonEnded = true
                    existingTenant.signedDeviceToken = nil
                    model.tenants[tenantData.slug] = existingTenant
                    
                    // Clear enrollments for this tenant
                    let tenantEnrollmentIds = existingTenant.enrollments
                    for enrollmentId in tenantEnrollmentIds {
                        model.enrollments.removeValue(forKey: enrollmentId)
                    }
                    existingTenant.enrollments.removeAll()
                    model.tenants[tenantData.slug] = existingTenant
                    
                    // Persist the changes
                    enrollmentRepository.persist(model: model)
                    
                    Logger.auth("✅ Updated domain model for season-ended tenant \(tenantData.slug)")
                }
            }
        }
        
        tenantInfo = newTenantInfo
    }
    
    // MARK: - Leaderboard Management
    func refreshLeaderboard(for tenantSlug: String, period: String = "season", teamId: String? = nil) {
        Logger.leaderboard("Refreshing leaderboard for tenant=\(tenantSlug) period=\(period) teamId=\(teamId ?? "nil")")
        guard let auth = model.tenants[tenantSlug]?.signedDeviceToken else { 
            Logger.error("No auth token for tenant \(tenantSlug) leaderboard refresh")
            return 
        }
        
        leaderboardRepository.fetchLeaderboard(tenant: tenantSlug, period: period, teamId: teamId, auth: auth) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let leaderboard):
                    Logger.success("Leaderboard fetch success, updating store")
                    self?.leaderboardErrors[tenantSlug] = nil  // Clear any previous error
                    self?.updateLeaderboard(leaderboard, for: tenantSlug, period: period)
                case .failure(let error):
                    Logger.error("Failed to refresh leaderboard for \(tenantSlug): \(error)")
                    Logger.error("Error details: \(error.localizedDescription)")
                    // Store user-friendly error message
                    self?.leaderboardErrors[tenantSlug] = self?.formatLeaderboardError(error) ?? "Kon leaderboard niet laden"
                }
            }
        }
    }
    
    private func updateLeaderboard(_ response: LeaderboardResponse, for tenantSlug: String, period: String) {
        let leaderboardData = LeaderboardData(
            tenantSlug: tenantSlug,
            tenantName: response.tenant.name,
            clubName: response.club?.name,
            clubLogoUrl: nil,  // Logo URLs now come from /tenants API
            period: period,
            teams: response.teams.map { teamEntry in
                LeaderboardTeam(
                    id: teamEntry.team.id,
                    name: teamEntry.team.name,
                    code: teamEntry.team.code,
                    rank: teamEntry.rank,
                    points: teamEntry.points,
                    totalHours: teamEntry.totalHours,
                    recentChange: teamEntry.recentChange,
                    positionChange: teamEntry.positionChange,
                    highlighted: teamEntry.highlighted
                )
            },
            leaderboardOptOut: response.tenant.leaderboardOptOut,
            lastUpdated: Date()
        )
        
        // Use the parameter tenantSlug as key (what the UI expects)
        // But also store under response slug if different (for debugging)
        leaderboards[tenantSlug] = leaderboardData
        if response.tenant.slug != tenantSlug {
            Logger.warning("Tenant slug mismatch: param=\(tenantSlug) response=\(response.tenant.slug)")
            leaderboards[response.tenant.slug] = leaderboardData
        }
        Logger.success("Updated leaderboard for \(tenantSlug): \(leaderboardData.teams.count) teams")
        Logger.debug("Leaderboard data stored with key: \(tenantSlug)")
        Logger.debug("Response tenant slug: \(response.tenant.slug)")
        Logger.debug("Parameter tenant slug: \(tenantSlug)")
        Logger.debug("Current leaderboards keys: \(Array(leaderboards.keys))")
    }
    
    private func formatLeaderboardError(_ error: Error) -> String {
        if let nsError = error as NSError? {
            if nsError.domain == "Backend" && nsError.code == -2 {
                return "Ongeldig antwoord ontvangen van server"
            }
            if nsError.localizedDescription.contains("Geen antwoord") {
                return "Geen verbinding met server"
            }
        }
        return "Kon leaderboard niet laden"
    }

    // MARK: - Deep links
    private func handleEnrollmentDeepLink(_ url: URL) {
        guard let token = DeepLink.extractToken(from: url) else { return }
        completeEnrollment(token: token) { _ in }
    }

    private func handleCTALink(_ url: URL) {
        // Example: kantinekoning://cta/shift-volunteer?token=...
        guard let token = DeepLink.extractToken(from: url) else { return }
        pendingCTA = .shiftVolunteer(token: token)
    }
    
    private func handleInviteLink(_ url: URL) {
        // Handle both kantinekoning://invite?... and https://kantinekoning.com/invite?...
        guard let params = DeepLink.extractInviteParams(from: url) else { return }
        Logger.userInteraction("Invite Link Received", target: "AppStore", context: [
            "tenant": params.tenant,
            "tenant_name": params.tenantName,
            "url_scheme": url.scheme ?? "unknown"
        ])
        
        // Always show enrollment flow for direct links - user might want to add more teams
        // Force the app to onboarding mode to show enrollment screen
        Logger.userInteraction("Invite Link - Forcing Enrollment Flow", target: "AppStore", context: [
            "tenant": params.tenant,
            "action": "forcing_enrollment_display"
        ])
        
        // Set app phase to onboarding to ensure enrollment screen is shown
        appPhase = .onboarding
        handleQRScan(slug: params.tenant, name: params.tenantName)
    }
}

// MARK: - Volunteer intents
extension AppStore {
    // MARK: - Team search & member enrollment
    func searchTeams(tenant: TenantID, query: String) {
        enrollmentRepository.searchTeams(tenant: tenant, query: query) { [weak self] result in
            DispatchQueue.main.async { if case .success(let items) = result { self?.searchResults = items } }
        }
    }

    func registerMember(tenantSlug: String, tenantName: String, teamIds: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        // Prevent duplicate member registration
        if isRegisteringMember {
            Logger.warning("⚠️ Member registration already in progress")
            completion(.failure(EnrollmentError.alreadyInProgress))
            return
        }
        
        isRegisteringMember = true
        Logger.auth("🔄 Starting member registration for tenant: \(tenantSlug)")
        
        enrollmentRepository.registerMember(tenantSlug: tenantSlug, tenantName: tenantName, teamIds: teamIds, pushToken: pushToken) { [weak self] result in
            guard let self = self else { return }
            
            // Always clean up registration flag
            self.isRegisteringMember = false
            
            switch result {
            case .success(let delta):
                DispatchQueue.main.async {
                    Logger.success("✅ Member registration completed for tenant: \(tenantSlug)")
                    
                    // Enforce dedup and max-5 like manager
                    var next = self.model
                    let existingCount = next.tenants.values.reduce(0) { $0 + $1.teams.count }
                    let availableSlots = max(0, 5 - existingCount)
                    let trimmedTeams = Array(delta.teams.prefix(availableSlots))
                    let trimmedDelta = EnrollmentDelta(tenant: delta.tenant, teams: trimmedTeams, signedDeviceToken: delta.signedDeviceToken)
                    next = next.applying(delta: trimmedDelta)
                    self.model = next
                    self.enrollmentRepository.persist(model: self.model)
                    self.appPhase = .registered
                    self.refreshDiensten()
                    
                    // CRITICAL: Ensure push notifications are configured for member enrollment too
                    self.configurePushNotifications()
                    
                    // Register push token with backend after member enrollment
                    if let token = self.pushToken, let anyAuthToken = self.model.primaryAuthToken {
                        Logger.push("Re-registering APNs token after member enrollment completion")
                        self.pushService.updateAPNs(token: token, auth: anyAuthToken)
                    } else {
                        Logger.push("⏳ Push token will be registered when received from iOS (member)")
                    }
                    completion(.success(()))
                }
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.network("Adding volunteer: finding best auth token")
        
        // Find the dienst to determine which team it belongs to
        guard let dienst = upcoming.first(where: { $0.id == dienstId }),
              let dienstTeamId = dienst.teamId else {
            Logger.error("Dienst \(dienstId) or team not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dienst not found"])))
            return
        }
        
        // Find tenant and check if we have manager access for this team
        guard let tenantData = model.tenants[tenant] else {
            Logger.error("Tenant \(tenant) not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tenant not found"])))
            return
        }
        
        // Check if we have manager role for this specific team
        // Note: dienstTeamId can be either team ID (UUID) or team code
        guard let actualTeam = tenantData.teams.first(where: { team in
            (team.id == dienstTeamId || team.code == dienstTeamId) && team.role == .manager
        }) else {
            Logger.error("No manager access for team \(dienstTeamId) - available teams: \(tenantData.teams.map { "id=\($0.id) code=\($0.code ?? "nil") role=\($0.role)" })")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment) - use actual team ID for lookup
        guard let authToken = model.authTokenForTeam(actualTeam.id, in: tenant) else {
            Logger.error("No auth token for team \(actualTeam.id) (\(actualTeam.name)) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        Logger.auth("Using enrollment-specific token for team \(actualTeam.name) (id=\(actualTeam.id)): \(authToken.prefix(20))...")
        
        // Use direct backend call with proper auth token, then refresh data model
        let backend = BackendClient()
        backend.authToken = authToken
        backend.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    Logger.volunteer("✅ Successfully added volunteer via API - refreshing data")
                    // Refresh the entire data model to get updated state
                    self?.refreshDiensten()
                    completion(.success(()))
                case .failure(let err):
                    Logger.volunteer("❌ Failed to add volunteer: \(err)")
                    self?.handlePotentialTokenRevocation(error: err, tenant: tenant)
                    completion(.failure(err))
                }
            }
        }
    }

    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.network("Removing volunteer: finding best auth token")
        
        // Find the dienst to determine which team it belongs to
        guard let dienst = upcoming.first(where: { $0.id == dienstId }),
              let dienstTeamId = dienst.teamId else {
            Logger.error("Dienst \(dienstId) or team not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dienst not found"])))
            return
        }
        
        // Find tenant and check if we have manager access for this team
        guard let tenantData = model.tenants[tenant] else {
            Logger.error("Tenant \(tenant) not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tenant not found"])))
            return
        }
        
        // Check if we have manager role for this specific team
        // Note: dienstTeamId can be either team ID (UUID) or team code
        guard let actualTeam = tenantData.teams.first(where: { team in
            (team.id == dienstTeamId || team.code == dienstTeamId) && team.role == .manager
        }) else {
            Logger.error("No manager access for team \(dienstTeamId) - available teams: \(tenantData.teams.map { "id=\($0.id) code=\($0.code ?? "nil") role=\($0.role)" })")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment) - use actual team ID for lookup
        guard let authToken = model.authTokenForTeam(actualTeam.id, in: tenant) else {
            Logger.error("No auth token for team \(actualTeam.id) (\(actualTeam.name)) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        Logger.auth("Using enrollment-specific token for team \(actualTeam.name) (id=\(actualTeam.id)): \(authToken.prefix(20))...")
        
        // Use direct backend call with proper auth token, then refresh data model
        let backend = BackendClient()
        backend.authToken = authToken
        backend.removeVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    Logger.volunteer("✅ Successfully removed volunteer via API - refreshing data")
                    // Refresh the entire data model to get updated state
                    self?.refreshDiensten()
                    completion(.success(()))
                case .failure(let err):
                    Logger.volunteer("❌ Failed to remove volunteer: \(err)")
                    self?.handlePotentialTokenRevocation(error: err, tenant: tenant)
                    completion(.failure(err))
                }
            }
        }
    }
    
    // MARK: - Optimistic Updates for Snappy UX
    
    /// Immediately add volunteer to UI for responsive UX (before API confirmation)
    func optimisticallyAddVolunteer(dienstId: String, name: String) {
        guard let index = upcoming.firstIndex(where: { $0.id == dienstId }) else {
            Logger.warning("Cannot find dienst \(dienstId) for optimistic add")
            return
        }
        
        let dienst = upcoming[index]
        var volunteers = dienst.volunteers ?? []
        
        // Add volunteer if not already present
        if !volunteers.contains(name) {
            volunteers.append(name)
            
            // Create new Dienst instance with updated volunteers
            let updatedDienst = Dienst(
                id: dienst.id,
                tenantId: dienst.tenantId,
                teamId: dienst.teamId,
                teamName: dienst.teamName,
                startTime: dienst.startTime,
                endTime: dienst.endTime,
                status: dienst.status,
                locationName: dienst.locationName,
                volunteers: volunteers,
                updatedAt: dienst.updatedAt,
                minimumBemanning: dienst.minimumBemanning
            )
            
            upcoming[index] = updatedDienst
            Logger.volunteer("🚀 Optimistically added '\(name)' to dienst \(dienstId) - UI updated instantly")
        }
    }
    
    /// Immediately remove volunteer from UI for responsive UX (before API confirmation)
    func optimisticallyRemoveVolunteer(dienstId: String, name: String) {
        guard let index = upcoming.firstIndex(where: { $0.id == dienstId }) else {
            Logger.warning("Cannot find dienst \(dienstId) for optimistic remove")
            return
        }
        
        let dienst = upcoming[index]
        var volunteers = dienst.volunteers ?? []
        
        // Remove volunteer if present
        if let volunteerIndex = volunteers.firstIndex(of: name) {
            volunteers.remove(at: volunteerIndex)
            
            // Create new Dienst instance with updated volunteers
            let updatedDienst = Dienst(
                id: dienst.id,
                tenantId: dienst.tenantId,
                teamId: dienst.teamId,
                teamName: dienst.teamName,
                startTime: dienst.startTime,
                endTime: dienst.endTime,
                status: dienst.status,
                locationName: dienst.locationName,
                volunteers: volunteers,
                updatedAt: dienst.updatedAt,
                minimumBemanning: dienst.minimumBemanning
            )
            
            upcoming[index] = updatedDienst
            Logger.volunteer("🚀 Optimistically removed '\(name)' from dienst \(dienstId) - UI updated instantly")
        }
    }
    
    /// Revert optimistic add if API call fails
    func revertOptimisticVolunteerAdd(dienstId: String, name: String) {
        guard let index = upcoming.firstIndex(where: { $0.id == dienstId }) else {
            Logger.warning("Cannot find dienst \(dienstId) for revert add")
            return
        }
        
        let dienst = upcoming[index]
        var volunteers = dienst.volunteers ?? []
        
        // Remove the optimistically added volunteer
        if let volunteerIndex = volunteers.firstIndex(of: name) {
            volunteers.remove(at: volunteerIndex)
            
            // Create new Dienst instance with reverted volunteers
            let revertedDienst = Dienst(
                id: dienst.id,
                tenantId: dienst.tenantId,
                teamId: dienst.teamId,
                teamName: dienst.teamName,
                startTime: dienst.startTime,
                endTime: dienst.endTime,
                status: dienst.status,
                locationName: dienst.locationName,
                volunteers: volunteers,
                updatedAt: dienst.updatedAt,
                minimumBemanning: dienst.minimumBemanning
            )
            
            upcoming[index] = revertedDienst
            Logger.volunteer("↩️ Reverted optimistic add of '\(name)' from dienst \(dienstId)")
        }
    }
    
    /// Revert optimistic remove if API call fails
    func revertOptimisticVolunteerRemove(dienstId: String, name: String) {
        guard let index = upcoming.firstIndex(where: { $0.id == dienstId }) else {
            Logger.warning("Cannot find dienst \(dienstId) for revert remove")
            return
        }
        
        let dienst = upcoming[index]
        var volunteers = dienst.volunteers ?? []
        
        // Add the volunteer back
        if !volunteers.contains(name) {
            volunteers.append(name)
            
            // Create new Dienst instance with reverted volunteers
            let revertedDienst = Dienst(
                id: dienst.id,
                tenantId: dienst.tenantId,
                teamId: dienst.teamId,
                teamName: dienst.teamName,
                startTime: dienst.startTime,
                endTime: dienst.endTime,
                status: dienst.status,
                locationName: dienst.locationName,
                volunteers: volunteers,
                updatedAt: dienst.updatedAt,
                minimumBemanning: dienst.minimumBemanning
            )
            
            upcoming[index] = revertedDienst
            Logger.volunteer("↩️ Reverted optimistic remove of '\(name)' - added back to dienst \(dienstId)")
        }
    }
    
    // MARK: - Auth token management
    // NOTE: We now use enrollment-specific tokens per operation instead of global auth tokens
    // Each operation creates its own BackendClient with the appropriate tenant-specific token
}

// MARK: - Review Request System
struct ReviewRequestTracker: Codable {
    private static let key = "kk_review_tracker"
    
    var requestCount: Int = 0
    var lastRequestDate: Date?
    var hasEverReviewed: Bool = false
    
    static func load() -> ReviewRequestTracker {
        guard let data = UserDefaults.standard.data(forKey: key),
              let tracker = try? JSONDecoder().decode(ReviewRequestTracker.self, from: data) else {
            return ReviewRequestTracker()
        }
        return tracker
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ReviewRequestTracker.key)
        }
    }
}

extension AppStore {
    static func requestReviewIfAppropriate() {
        var tracker = ReviewRequestTracker.load()
        
        // Never ask if they've already reviewed
        guard !tracker.hasEverReviewed else { return }
        
        // If we've used all 3 attempts, wait a full year
        if tracker.requestCount >= 3 {
            if let lastRequest = tracker.lastRequestDate {
                let daysSinceLastRequest = Calendar.current.dateComponents([.day], from: lastRequest, to: Date()).day ?? 0
                guard daysSinceLastRequest >= 365 else { return }
                
                // Reset after a year
                tracker.requestCount = 0
            }
        }
        
        // Make the request
        tracker.requestCount += 1
        tracker.lastRequestDate = Date()
        tracker.save()
        
        Logger.userInteraction("Review Request", target: "SKStoreReviewController", context: [
            "attempt": tracker.requestCount,
            "context": "post_confetti_success"
        ])
        
        // Request review using modern API with fallback
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if #available(iOS 18.0, *) {
                // Use new StoreKit.AppStore API for iOS 18+
                Task {
                    await StoreKit.AppStore.requestReview(in: scene)
                }
            } else {
                // Use legacy API for iOS 16-17
                SKStoreReviewController.requestReview(in: scene)
            }
        } else {
            Logger.error("[ReviewRequest] No window scene available for review request")
        }
    }
    
    // Optional: Mark as reviewed if user goes to App Store
    static func markAsReviewed() {
        var tracker = ReviewRequestTracker.load()
        tracker.hasEverReviewed = true
        tracker.save()
        Logger.userInteraction("User Reviewed", target: "AppStore", context: [:])
    }
}

// MARK: - CTA
extension AppStore {
    func performCTA() {
        guard let cta = pendingCTA else { return }
        switch cta {
        case .shiftVolunteer:
            // In a real app, fetch CTA metadata and present a sheet. Here we just clear.
            pendingCTA = nil
        }
    }
}

// MARK: - Notification Permission Card helpers
extension AppStore {
    enum NotificationStatus { case authorized, denied, notDetermined }
    func getNotificationStatus(completion: @escaping (NotificationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: completion(.authorized)
            case .denied: completion(.denied)
            case .notDetermined: completion(.notDetermined)
            @unknown default: completion(.denied)
            }
        }
    }
}

private extension Array where Element == Dienst {
    mutating func replace(with updated: Dienst) {
        if let idx = firstIndex(where: { $0.id == updated.id }) {
            self[idx] = updated
        } else {
            self.append(updated)
        }
    }
}



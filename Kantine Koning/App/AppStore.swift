import Foundation
import Combine
import UserNotifications

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
    @Published var globalLeaderboard: GlobalLeaderboardData?
    @Published var tenantInfo: [String: TenantInfo] = [:] // tenantSlug -> TenantInfo (club logos etc.)
    
    // Network connectivity
    @Published var isOnline: Bool = true
    let networkMonitor = NetworkMonitor.shared

    // Services
    private let enrollmentRepository: EnrollmentRepository
    private let dienstRepository: DienstRepository
    private let pushService: PushService
    private let leaderboardRepository: LeaderboardRepository

    private var cancellables: Set<AnyCancellable> = []

    init(
        enrollmentRepository: EnrollmentRepository = DefaultEnrollmentRepository(),
        dienstRepository: DienstRepository = CachedDienstRepository(),
        pushService: PushService = DefaultPushService(),
        leaderboardRepository: LeaderboardRepository = CachedLeaderboardRepository()
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
        
        // Setup cache cleanup
        CacheManager.shared.cleanupExpiredEntries()
        Logger.bootstrap("Cache cleanup completed")
        
        if model.isEnrolled { 
            Logger.bootstrap("User enrolled - refreshing diensten")
            refreshDiensten() 
        } else {
            Logger.bootstrap("User not enrolled - showing onboarding")
        }
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
    }

    func setPushToken(_ token: String) { 
        self.pushToken = token
        // Register APNs token once with any available enrollment token
        // Backend will update all enrollments for this device
        if let anyAuthToken = model.tenants.values.first?.signedDeviceToken {
            Logger.push("Registering APNs token with backend using any available auth token")
            pushService.updateAPNs(token: token, auth: anyAuthToken)
        } else {
            Logger.push("No auth tokens available for APNs registration")
        }
    }
    func handlePushRegistrationFailure(_ error: Error) { Logger.error("APNs failure: \(error)") }
    func handleNotification(userInfo: [AnyHashable: Any]) { /* map to actions if needed */ }

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
        if let anyToken = model.tenants.values.first?.signedDeviceToken {
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
        enrollmentRepository.registerDevice(enrollmentToken: token, pushToken: pushToken) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let delta):
                DispatchQueue.main.async {
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
                    // Register push token with backend (once, using any available auth token)
                    if let token = self.pushToken, let anyAuthToken = self.model.tenants.values.first?.signedDeviceToken {
                        Logger.push("Re-registering APNs token after enrollment completion")
                        self.pushService.updateAPNs(token: token, auth: anyAuthToken)
                    }
                    completion(.success(()))
                }
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    func removeTenant(_ tenant: TenantID) {
        Logger.debug("🗑️ Removing tenant: \(tenant)")
        
        // Get the specific tenant's token before removing it from the model
        let tenantToken = model.tenants[tenant]?.signedDeviceToken
        Logger.debug("Tenant-specific auth token available: \(tenantToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTenant(tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        Logger.success("Local tenant removal complete")
        
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
            
            tempBackend.removeTeams([team]) { result in
                Logger.network("Backend team removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            Logger.warning("No enrollment-specific auth token - member enrollment, local removal only")
        }
    }

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
    
    func refreshTenantInfo() {
        // Check cache first
        let cacheKey = CacheManager.CacheKey.allTenantInfo
        let cachedResult = CacheManager.shared.getCached(TenantInfoResponse.self, forKey: cacheKey)
        
        // Use cached data immediately if available
        if let cachedResponse = cachedResult.data {
            Logger.debug("Using cached tenant info for \(cachedResponse.tenants.count) tenants")
            updateTenantInfoFromResponse(cachedResponse)
        }
        
        // Always fetch fresh data (background refresh if cached data exists)
        guard let anyToken = model.tenants.values.first?.signedDeviceToken else {
            Logger.warning("No auth token available for tenant info")
            return
        }
        
        let backend = BackendClient()
        backend.authToken = anyToken
        
        backend.fetchTenantInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    Logger.success("Received fresh tenant info for \(response.tenants.count) tenants")
                    
                    // Cache with long TTL (tenant info doesn't change often)
                    CacheManager.shared.cache(response, forKey: cacheKey, ttl: 3600) // 1 hour
                    
                    self?.updateTenantInfoFromResponse(response)
                    
                case .failure(let error):
                    Logger.error("Failed to fetch tenant info: \(error)")
                    // Don't override cached data on error
                }
            }
        }
    }
    
    private func updateTenantInfoFromResponse(_ response: TenantInfoResponse) {
        var newTenantInfo: [String: TenantInfo] = [:]
        
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
                teams: teams
            )
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
                    self?.updateLeaderboard(leaderboard, for: tenantSlug, period: period)
                case .failure(let error):
                    Logger.error("Failed to refresh leaderboard for \(tenantSlug): \(error)")
                    Logger.error("Error details: \(error.localizedDescription)")
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
        enrollmentRepository.registerMember(tenantSlug: tenantSlug, tenantName: tenantName, teamIds: teamIds, pushToken: pushToken) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let delta):
                DispatchQueue.main.async {
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
        let hasManagerAccess = tenantData.teams.contains { team in
            team.id == dienstTeamId && team.role == .manager
        }
        
        guard hasManagerAccess else {
            Logger.error("No manager access for team \(dienstTeamId)")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment)
        guard let authToken = model.authTokenForTeam(dienstTeamId, in: tenant) else {
            Logger.error("No auth token for team \(dienstTeamId) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        Logger.auth("Using enrollment-specific token for team \(dienstTeamId): \(authToken.prefix(20))...")
        
        let backend = BackendClient()
        backend.authToken = authToken
        backend.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    // Update the dienst in our local list
                    if let index = self?.upcoming.firstIndex(where: { $0.id == dienstId }) {
                        let updatedDienst = Dienst(
                            id: updated.id,
                            tenantId: updated.tenant_id,
                            teamId: updated.team?.id,
                            startTime: updated.start_tijd,
                            endTime: updated.eind_tijd,
                            status: updated.status,
                            locationName: updated.locatie_naam,
                            volunteers: updated.aanmeldingen,
                            updatedAt: updated.updated_at,
                            minimumBemanning: updated.minimum_bemanning
                        )
                        self?.upcoming[index] = updatedDienst
                    }
                    // Force refresh to ensure UI consistency after volunteer add
                    self?.refreshDiensten()
                    completion(.success(()))
                case .failure(let err):
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
        let hasManagerAccess = tenantData.teams.contains { team in
            team.id == dienstTeamId && team.role == .manager
        }
        
        guard hasManagerAccess else {
            Logger.error("No manager access for team \(dienstTeamId)")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment)
        guard let authToken = model.authTokenForTeam(dienstTeamId, in: tenant) else {
            Logger.error("No auth token for team \(dienstTeamId) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        Logger.auth("Using enrollment-specific token for team \(dienstTeamId): \(authToken.prefix(20))...")
        
        let backend = BackendClient()
        backend.authToken = authToken
        backend.removeVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    // Update the dienst in our local list
                    if let index = self?.upcoming.firstIndex(where: { $0.id == dienstId }) {
                        let updatedDienst = Dienst(
                            id: updated.id,
                            tenantId: updated.tenant_id,
                            teamId: updated.team?.id,
                            startTime: updated.start_tijd,
                            endTime: updated.eind_tijd,
                            status: updated.status,
                            locationName: updated.locatie_naam,
                            volunteers: updated.aanmeldingen,
                            updatedAt: updated.updated_at,
                            minimumBemanning: updated.minimum_bemanning
                        )
                        self?.upcoming[index] = updatedDienst
                    }
                    // Force refresh to ensure UI consistency after volunteer remove
                    self?.refreshDiensten()
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }
    
    // MARK: - Auth token management
    // NOTE: We now use enrollment-specific tokens per operation instead of global auth tokens
    // Each operation creates its own BackendClient with the appropriate tenant-specific token
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



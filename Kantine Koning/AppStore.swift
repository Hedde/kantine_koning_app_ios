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

    // Services
    private let enrollmentRepository: EnrollmentRepository
    private let dienstRepository: DienstRepository
    private let pushService: PushService
    private let leaderboardRepository: LeaderboardRepository

    private var cancellables: Set<AnyCancellable> = []

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
        self.model = enrollmentRepository.loadModel()
        self.appPhase = model.isEnrolled ? .registered : .onboarding
        if model.isEnrolled { refreshDiensten() }
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
            print("[AppStore] 📱 Registering APNs token with backend using any available auth token")
            pushService.updateAPNs(token: token, auth: anyAuthToken)
        } else {
            print("[AppStore] ⚠️ No auth tokens available for APNs registration")
        }
    }
    func handlePushRegistrationFailure(_ error: Error) { print("APNs failure: \(error)") }
    func handleNotification(userInfo: [AnyHashable: Any]) { /* map to actions if needed */ }

    func configurePushNotifications() {
        pushService.requestAuthorization()
    }

    func startNewEnrollment() { 
        print("[Onboarding] 🔄 Starting fresh enrollment flow")
        // Clear all onboarding state for clean start
        onboardingScan = nil
        searchResults = []
        appPhase = .onboarding
        print("[Onboarding] ✅ Onboarding state cleared")
    }
    func resetAll() {
        print("[Reset] 🗑️ Starting full app reset...")
        print("[Reset] 📊 Current model has \(model.tenants.count) tenants")
        
        // Call backend to remove all enrollments using any available token
        if let anyToken = model.tenants.values.first?.signedDeviceToken {
            print("[Reset] 📡 Calling backend removeAllEnrollments with token: \(anyToken.prefix(20))...")
            enrollmentRepository.removeAllEnrollments { [weak self] result in
                print("[Reset] 📥 Backend removeAll completed with result: \(result)")
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("[Reset] ✅ Backend reset successful")
                    case .failure(let error):
                        print("[Reset] ❌ Backend reset failed: \(error)")
                    }
                    // Always clear local state regardless
                    self?.clearLocalState()
                }
            }
        } else {
            print("[Reset] ⚠️ No auth token for backend reset, clearing local only")
            clearLocalState()
        }
    }
    
    private func clearLocalState() {
        print("[Reset] 🧹 Clearing local state...")
        print("[Reset] 📊 Before clear: \(model.tenants.count) tenants, \(upcoming.count) diensten")
        
        // Clear local state (auth tokens are now handled per-operation)
        
        model = .empty
        upcoming = []
        searchResults = []
        onboardingScan = nil
        pushToken = nil
        print("[Reset] 📊 After clear: \(model.tenants.count) tenants, \(upcoming.count) diensten")
        print("[Reset] 🎯 Setting appPhase to .onboarding")
        appPhase = .onboarding
        enrollmentRepository.persist(model: model)
        print("[Reset] ✅ Local reset complete - should now see onboarding")
    }

    // QR handling: a simplified representation of scanned tenant
    struct ScannedTenant { let slug: TenantID; let name: String }
    func handleQRScan(slug: TenantID, name: String) { onboardingScan = ScannedTenant(slug: slug, name: name) }

    enum CTA: Equatable { case shiftVolunteer(token: String) }

    func submitEmail(_ email: String, for tenant: TenantID, selectedTeamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        // Old flow: if no team codes yet, first fetch allowed teams for selection
        if selectedTeamCodes.isEmpty {
            print("[Enroll] 🔎 fetching allowed teams for email=\(email) tenant=\(tenant)")
            enrollmentRepository.fetchAllowedTeams(email: email, tenant: tenant) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let teams):
                        print("[Enroll] ✅ allowed teams count=\(teams.count)")
                        // In a full flow, we would present team selection here.
                        // For now, keep state for UI to show selection in onboarding.
                        self?.searchResults = teams
                        completion(.success(()))
                    case .failure(let err):
                        print("[Enroll] ❌ fetch allowed teams: \(err)")
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
                        print("[AppStore] 📱 Re-registering APNs token after enrollment completion")
                        self.pushService.updateAPNs(token: token, auth: anyAuthToken)
                    }
                    completion(.success(()))
                }
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    func removeTenant(_ tenant: TenantID) {
        print("[AppStore] 🗑️ Removing tenant: \(tenant)")
        
        // Get the specific tenant's token before removing it from the model
        let tenantToken = model.tenants[tenant]?.signedDeviceToken
        print("[AppStore] 🔍 Tenant-specific auth token available: \(tenantToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTenant(tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        print("[AppStore] ✅ Local tenant removal complete")
        
        // Try backend removal if we have the tenant's auth token
        if let token = tenantToken {
            // Create a temporary backend client with the specific tenant's token
            let tempBackend = BackendClient()
            tempBackend.authToken = token
            print("[AppStore] 🔑 Using tenant-specific token for removal")
            
            tempBackend.removeTenant(tenant) { result in
                print("[AppStore] 📡 Backend tenant removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            print("[AppStore] ⚠️ No tenant-specific auth token - member enrollment, local removal only")
        }
    }

    func removeTeam(_ team: TeamID, from tenant: TenantID) {
        print("[AppStore] 🗑️ Removing team: \(team) from tenant: \(tenant)")
        
        // Get the specific token for this team/tenant before removing it from the model
        let authToken = model.authTokenForTeam(team, in: tenant)
        print("[AppStore] 🔍 Team-specific auth token available: \(authToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTeam(team, from: tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        print("[AppStore] ✅ Local team removal complete")
        
        // Try backend removal if we have the team's auth token
        if let token = authToken {
            // Create a temporary backend client with the specific token
            let tempBackend = BackendClient()
            tempBackend.authToken = token
            print("[AppStore] 🔑 Using enrollment-specific token for team removal")
            
            tempBackend.removeTeams([team]) { result in
                print("[AppStore] 📡 Backend team removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            print("[AppStore] ⚠️ No enrollment-specific auth token - member enrollment, local removal only")
        }
    }

    func refreshDiensten() {
        guard model.isEnrolled else { return }
        print("[AppStore] 🔄 Refreshing diensten for \(model.tenants.count) tenants")
        for (slug, tenant) in model.tenants {
            print("[AppStore]   → tenant \(slug): \(tenant.teams.count) teams")
            for team in tenant.teams {
                print("[AppStore]     → team id=\(team.id) code=\(team.code ?? "nil") name=\(team.name)")
            }
        }
        
        // Preload leaderboard data for club logos (background fetch)
        preloadLeaderboardData()
        
        // Fetch diensten using enrollment-specific tokens (handled in repository)
        dienstRepository.fetchUpcoming(for: model) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result { 
                    print("[AppStore] ✅ Received \(items.count) diensten")
                    self?.upcoming = items 
                }
            }
        }
    }
    
    private func preloadLeaderboardData() {
        // Preload tenant info (including club logos) - more efficient than leaderboard data
        refreshTenantInfo()
    }
    
    func refreshTenantInfo() {
        // Use any available token to fetch tenant info for all enrollments
        guard let anyToken = model.tenants.values.first?.signedDeviceToken else {
            print("[AppStore] ⚠️ No auth token available for tenant info")
            return
        }
        
        let backend = BackendClient()
        backend.authToken = anyToken
        
        backend.fetchTenantInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("[AppStore] ✅ Received tenant info for \(response.tenants.count) tenants")
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
                    
                    self?.tenantInfo = newTenantInfo
                    
                case .failure(let error):
                    print("[AppStore] ❌ Failed to fetch tenant info: \(error)")
                }
            }
        }
    }
    
    // MARK: - Leaderboard Management
    func refreshLeaderboard(for tenantSlug: String, period: String = "season", teamId: String? = nil) {
        print("[Store] 🔄 Refreshing leaderboard for tenant=\(tenantSlug) period=\(period) teamId=\(teamId ?? "nil")")
        guard let auth = model.tenants[tenantSlug]?.signedDeviceToken else { 
            print("[Store] ❌ No auth token for tenant \(tenantSlug) leaderboard refresh")
            return 
        }
        
        leaderboardRepository.fetchLeaderboard(tenant: tenantSlug, period: period, teamId: teamId, auth: auth) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let leaderboard):
                    print("[Store] ✅ Leaderboard fetch success, updating store")
                    self?.updateLeaderboard(leaderboard, for: tenantSlug, period: period)
                case .failure(let error):
                    print("[Store] ❌ Failed to refresh leaderboard for \(tenantSlug): \(error)")
                    print("[Store] ❌ Error details: \(error.localizedDescription)")
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
            print("[Store] ⚠️ Tenant slug mismatch: param=\(tenantSlug) response=\(response.tenant.slug)")
            leaderboards[response.tenant.slug] = leaderboardData
        }
        print("[Store] ✅ Updated leaderboard for \(tenantSlug): \(leaderboardData.teams.count) teams")
        print("[Store] 📊 Leaderboard data stored with key: \(tenantSlug)")
        print("[Store] 📊 Response tenant slug: \(response.tenant.slug)")
        print("[Store] 📊 Parameter tenant slug: \(tenantSlug)")
        print("[Store] 📊 Current leaderboards keys: \(Array(leaderboards.keys))")
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
        print("[AppStore] 📡 Adding volunteer: finding best auth token")
        
        // Find the dienst to determine which team it belongs to
        guard let dienst = upcoming.first(where: { $0.id == dienstId }),
              let dienstTeamId = dienst.teamId else {
            print("[AppStore] ❌ Dienst \(dienstId) or team not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dienst not found"])))
            return
        }
        
        // Find tenant and check if we have manager access for this team
        guard let tenantData = model.tenants[tenant] else {
            print("[AppStore] ❌ Tenant \(tenant) not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tenant not found"])))
            return
        }
        
        // Check if we have manager role for this specific team
        let hasManagerAccess = tenantData.teams.contains { team in
            team.id == dienstTeamId && team.role == .manager
        }
        
        guard hasManagerAccess else {
            print("[AppStore] ❌ No manager access for team \(dienstTeamId)")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment)
        guard let authToken = model.authTokenForTeam(dienstTeamId, in: tenant) else {
            print("[AppStore] ❌ No auth token for team \(dienstTeamId) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        print("[AppStore] 🔑 Using enrollment-specific token for team \(dienstTeamId): \(authToken.prefix(20))...")
        
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
                            teamId: updated.team?.code ?? updated.team?.id,
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
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[AppStore] 📡 Removing volunteer: finding best auth token")
        
        // Find the dienst to determine which team it belongs to
        guard let dienst = upcoming.first(where: { $0.id == dienstId }),
              let dienstTeamId = dienst.teamId else {
            print("[AppStore] ❌ Dienst \(dienstId) or team not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Dienst not found"])))
            return
        }
        
        // Find tenant and check if we have manager access for this team
        guard let tenantData = model.tenants[tenant] else {
            print("[AppStore] ❌ Tenant \(tenant) not found")
            completion(.failure(NSError(domain: "AppStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tenant not found"])))
            return
        }
        
        // Check if we have manager role for this specific team
        let hasManagerAccess = tenantData.teams.contains { team in
            team.id == dienstTeamId && team.role == .manager
        }
        
        guard hasManagerAccess else {
            print("[AppStore] ❌ No manager access for team \(dienstTeamId)")
            completion(.failure(NSError(domain: "AppStore", code: 403, userInfo: [NSLocalizedDescriptionKey: "No manager access for this team"])))
            return
        }
        
        // Use specific token for this team (from enrollment)
        guard let authToken = model.authTokenForTeam(dienstTeamId, in: tenant) else {
            print("[AppStore] ❌ No auth token for team \(dienstTeamId) in tenant \(tenant)")
            completion(.failure(NSError(domain: "AppStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token for this team"])))
            return
        }
        
        print("[AppStore] 🔑 Using enrollment-specific token for team \(dienstTeamId): \(authToken.prefix(20))...")
        
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
                            teamId: updated.team?.code ?? updated.team?.id,
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



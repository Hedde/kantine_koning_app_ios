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

    func setPushToken(_ token: String) { self.pushToken = token; pushService.updateAPNs(token: token, auth: model.primaryAuthToken) }
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
        
        // Call backend to remove all enrollments first
        if let authToken = model.primaryAuthToken {
            print("[Reset] 📡 Calling backend removeAllEnrollments with token: \(authToken.prefix(20))...")
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
        
        // Clear backend auth token first
        enrollmentRepository.setAuthToken("")
        dienstRepository.setAuthToken("")
        pushService.setAuthToken("")
        
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
                    if let token = self.pushToken, let auth = self.model.primaryAuthToken { self.pushService.updateAPNs(token: token, auth: auth) }
                    completion(.success(()))
                }
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    func removeTenant(_ tenant: TenantID) {
        print("[AppStore] 🗑️ Removing tenant: \(tenant)")
        print("[AppStore] 🔍 Auth token available: \(model.primaryAuthToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTenant(tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        print("[AppStore] ✅ Local tenant removal complete")
        
        // Try backend removal if we have auth (managers only)
        if model.primaryAuthToken != nil {
            enrollmentRepository.removeTenant(tenant) { result in
                print("[AppStore] 📡 Backend tenant removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            print("[AppStore] ⚠️ No auth token - member enrollment, local removal only")
        }
    }

    func removeTeam(_ team: TeamID, from tenant: TenantID) {
        print("[AppStore] 🗑️ Removing team: \(team) from tenant: \(tenant)")
        print("[AppStore] 🔍 Auth token available: \(model.primaryAuthToken != nil)")
        
        // Always update local state first for immediate UI feedback
        let updatedModel = model.removingTeam(team, from: tenant)
        model = updatedModel
        enrollmentRepository.persist(model: model)
        print("[AppStore] ✅ Local team removal complete")
        
        // Try backend removal if we have auth (managers only)
        if model.primaryAuthToken != nil {
            enrollmentRepository.removeTeams([team]) { result in
                print("[AppStore] 📡 Backend team removal result: \(result)")
                // Local state already updated, so no need to update again
            }
        } else {
            print("[AppStore] ⚠️ No auth token - member enrollment, local removal only")
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
        
        // Ensure auth token is set before fetching diensten
        ensureBackendAuthToken()
        
        dienstRepository.fetchUpcoming(for: model) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result { 
                    print("[AppStore] ✅ Received \(items.count) diensten")
                    self?.upcoming = items 
                }
            }
        }
    }
    
    // MARK: - Leaderboard Management
    func refreshLeaderboard(for tenantSlug: String, period: String = "season", teamId: String? = nil) {
        print("[Store] 🔄 Refreshing leaderboard for tenant=\(tenantSlug) period=\(period) teamId=\(teamId ?? "nil")")
        guard let auth = model.primaryAuthToken else { 
            print("[Store] ❌ No auth token for leaderboard refresh")
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
            clubLogoUrl: response.club?.logoUrl,
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
        print("[AppStore] 📡 Adding volunteer: ensuring auth token is set")
        ensureBackendAuthToken()
        dienstRepository.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self?.upcoming.replace(with: updated)
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[AppStore] 📡 Removing volunteer: ensuring auth token is set")
        ensureBackendAuthToken()
        dienstRepository.removeVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self?.upcoming.replace(with: updated)
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }
    
    // MARK: - Auth token management
    private func ensureBackendAuthToken() {
        if let token = model.primaryAuthToken {
            print("[AppStore] 🔑 Setting backend auth token: \(token.prefix(20))...")
            // Update all backend clients with current token
            enrollmentRepository.setAuthToken(token)
            dienstRepository.setAuthToken(token)
            pushService.setAuthToken(token)
        } else {
            print("[AppStore] ⚠️ No auth token available for backend calls")
        }
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



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

    // Services
    private let enrollmentRepository: EnrollmentRepository
    private let dienstRepository: DienstRepository
    private let pushService: PushService

    private var cancellables: Set<AnyCancellable> = []

    init(
        enrollmentRepository: EnrollmentRepository = DefaultEnrollmentRepository(),
        dienstRepository: DienstRepository = DefaultDienstRepository(),
        pushService: PushService = DefaultPushService()
    ) {
        self.enrollmentRepository = enrollmentRepository
        self.dienstRepository = dienstRepository
        self.pushService = pushService

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

    func startNewEnrollment() { appPhase = .onboarding }
    func resetAll() {
        model = .empty
        upcoming = []
        searchResults = []
        onboardingScan = nil
        pushToken = nil
        appPhase = .onboarding
        enrollmentRepository.persist(model: model)
    }

    // QR handling: a simplified representation of scanned tenant
    struct ScannedTenant { let slug: TenantID; let name: String }
    func handleQRScan(slug: TenantID, name: String) { onboardingScan = ScannedTenant(slug: slug, name: name) }

    func submitEmail(_ email: String, for tenant: TenantID, selectedTeamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        enrollmentRepository.requestEnrollment(email: email, tenant: tenant, teamCodes: selectedTeamCodes) { [weak self] result in
            switch result {
            case .success:
                DispatchQueue.main.async { self?.appPhase = .enrollmentPending(EnrollmentContext(tenant: tenant, issuedAt: Date())); completion(.success(())) }
            case .failure(let err): completion(.failure(err))
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
        enrollmentRepository.removeTenant(tenant) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.model = self.model.removingTenant(tenant)
                self.enrollmentRepository.persist(model: self.model)
            }
        }
    }

    func removeTeam(_ team: TeamID, from tenant: TenantID) {
        enrollmentRepository.removeTeams([team]) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.model = self.model.removingTeam(team, from: tenant)
                self.enrollmentRepository.persist(model: self.model)
            }
        }
    }

    func refreshDiensten() {
        guard model.isEnrolled else { return }
        dienstRepository.fetchUpcoming(for: model) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result { self?.upcoming = items }
            }
        }
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
}

// MARK: - CTA
extension AppStore {
    enum CTA { case shiftVolunteer(token: String) }
    @Published var pendingCTA: CTA?

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
            case .authorized, .provisional: completion(.authorized)
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



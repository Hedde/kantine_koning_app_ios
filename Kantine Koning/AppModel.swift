//
//  AppModel.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import Foundation
import Combine

final class AppModel: ObservableObject {
    enum AppPhase: Equatable {
        case launching
        case onboarding
        case enrollmentPending(EnrollmentContext)
        case registered
    }

    enum EnrollmentRole: String, Codable, Equatable {
        case manager
        case member
    }

    struct TenantInvite: Equatable {
        let tenantId: String
        let tenantName: String
        let allowedTeams: [Team]
    }

    struct Team: Equatable, Identifiable, Codable {
        let id: String
        let code: String?
        let naam: String
    }

    struct TenantContext: Equatable {
        let tenantId: String
        let tenantName: String
        var selectedTeams: [Team]
        var email: String
    }

    struct EnrollmentContext: Equatable {
        let tenantContext: TenantContext
        let issuedAt: Date
    }

    struct Enrollment: Equatable, Codable, Identifiable {
        var id: String { deviceId }
        let deviceId: String
        let deviceToken: String
        let tenantId: String
        let tenantName: String
        let teamIds: [String]
        let email: String?
        let role: EnrollmentRole
        let signedDeviceToken: String?

        private enum CodingKeys: String, CodingKey {
            case deviceId, deviceToken, tenantId, tenantName, teamIds, email, role, signedDeviceToken
        }

        init(deviceId: String, deviceToken: String, tenantId: String, tenantName: String, teamIds: [String], email: String?, role: EnrollmentRole, signedDeviceToken: String?) {
            self.deviceId = deviceId
            self.deviceToken = deviceToken
            self.tenantId = tenantId
            self.tenantName = tenantName
            self.teamIds = teamIds
            self.email = email
            self.role = role
            self.signedDeviceToken = signedDeviceToken
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deviceId = try container.decode(String.self, forKey: .deviceId)
            deviceToken = try container.decode(String.self, forKey: .deviceToken)
            tenantId = try container.decode(String.self, forKey: .tenantId)
            tenantName = try container.decode(String.self, forKey: .tenantName)
            teamIds = try container.decode([String].self, forKey: .teamIds)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            role = (try container.decodeIfPresent(EnrollmentRole.self, forKey: .role)) ?? .manager
            signedDeviceToken = try container.decodeIfPresent(String.self, forKey: .signedDeviceToken)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(deviceToken, forKey: .deviceToken)
            try container.encode(tenantId, forKey: .tenantId)
            try container.encode(tenantName, forKey: .tenantName)
            try container.encode(teamIds, forKey: .teamIds)
            try container.encodeIfPresent(email, forKey: .email)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(signedDeviceToken, forKey: .signedDeviceToken)
        }
    }

    @Published var appPhase: AppPhase = .launching
    @Published var pushToken: String?
    @Published var enrollments: [Enrollment] = [] {
        didSet {
            SecureStorage.shared.storeEnrollments(enrollments)
            // Keep BackendClient auth token in sync (prefer manager token if available)
            if let token = (enrollments.first(where: { $0.role == .manager && $0.signedDeviceToken != nil })?.signedDeviceToken
                            ?? enrollments.first(where: { $0.signedDeviceToken != nil })?.signedDeviceToken) {
                backend.authToken = token
            }
        }
    }
    @Published var invite: TenantInvite?
    @Published var tenantContext: TenantContext?
    @Published var upcomingDiensten: [Dienst] = []
    @Published var pendingAction: CTAAction?
    @Published var deepLinkNavigation: DeepLinkNavigation?
    @Published var verifiedEmail: String? // Store verified email for security validation

    let backend: BackendClient

    private var cancellables: Set<AnyCancellable> = []

    init(backend: BackendClient = BackendClient()) {
        self.backend = backend
        self.enrollments = SecureStorage.shared.loadEnrollments()
        if !enrollments.isEmpty {
            // Bootstrap auth token from stored enrollments (prefer manager token)
            if let token = (enrollments.first(where: { $0.role == .manager && $0.signedDeviceToken != nil })?.signedDeviceToken
                            ?? enrollments.first(where: { $0.signedDeviceToken != nil })?.signedDeviceToken) {
                self.backend.authToken = token
            }
            appPhase = .registered
            loadUpcomingDiensten()
        } else {
            appPhase = .onboarding
        }
    }

    func setPushToken(_ token: String) {
        pushToken = token
        print("🔄 Setting push token: \(token)")
        print("🔍 Debug: backend.authToken is \(backend.authToken?.prefix(20) ?? "nil")")
        // Only upload if we have auth; otherwise wait for enrollment completion
        guard let authToken = backend.authToken, !authToken.isEmpty else {
            print("⚠️ No auth token yet, will upload APNs token after enrollment")
            return
        }
        print("🔄 Uploading APNs token immediately (have auth)")
        // Propagate APNs token to backend when available
        backend.updateAPNSToken(apnsToken: token) { result in
            switch result {
            case .success:
                print("✅ APNs token uploaded to backend")
            case .failure(let error):
                print("❌ Failed to upload APNs token: \(error)")
            }
        }
    }

    func resetAll() {
        // Call backend API to remove all enrollments first
        backend.removeAllEnrollments { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Successfully removed all enrollments from backend")
                case .failure(let error):
                    print("❌ Failed to remove all enrollments from backend: \(error)")
                    // Continue with local reset even if backend fails
                }
                
                // Always update local state regardless of backend result
                self?.updateLocalStateAfterCompleteReset()
            }
        }
    }
    
    private func updateLocalStateAfterCompleteReset() {
        SecureStorage.shared.clearAll()
        enrollments = []
        invite = nil
        tenantContext = nil
        appPhase = .onboarding
        upcomingDiensten = []
        pushToken = nil // Force re-registration of push token
        
        print("🗑️ Completed full app reset")
    }

    func handleScannedInvite(_ invite: TenantInvite) {
        self.invite = invite
        self.tenantContext = TenantContext(tenantId: invite.tenantId, tenantName: invite.tenantName, selectedTeams: [], email: "")
    }

    func setSelectedTeams(_ teams: [Team]) {
        guard var context = tenantContext else { return }
        context.selectedTeams = teams
        tenantContext = context
    }

    func submitEmail(_ email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard var context = tenantContext else {
            completion(.failure(NSError(domain: "AppModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing tenant context"])));
            return
        }
        context.email = email
        tenantContext = context

        let teamCodes = context.selectedTeams.compactMap { $0.code ?? $0.naam }
        backend.enrollDevice(email: email, tenantSlug: context.tenantId, teamCodes: teamCodes) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.appPhase = .enrollmentPending(EnrollmentContext(tenantContext: context, issuedAt: Date()))
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // Removed simulateOpenMagicLink; enrollment flows via backend email confirmation

    func handleIncomingURL(_ url: URL) {
        if url.scheme == "kantinekoning" {
            handleCustomScheme(url)
            return
        }
        if url.host?.contains("kantinekoning.com") == true {
            handleWebLink(url)
            return
        }
    }

    private func handleCustomScheme(_ url: URL) {
        // kantinekoning://device-enroll?token=...
        // kantinekoning://cta/shift-volunteer?token=...
        guard let host = url.host else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        if host == "device-enroll", let token {
            handleEnrollmentDeepLink(token: token) { _ in }
        } else if host == "cta", url.path.contains("shift-volunteer"), let token {
            handleCTADeepLink(token: token)
        }
    }

    private func handleWebLink(_ url: URL) {
        // https://kantinekoning.com/device-enroll?token=...
        // https://kantinekoning.com/cta/shift-volunteer?token=...
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        if url.path.contains("device-enroll"), let token {
            handleEnrollmentDeepLink(token: token) { _ in }
        } else if url.path.contains("shift-volunteer"), let token {
            handleCTADeepLink(token: token)
        }
    }

    func handleEnrollmentDeepLink(token: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let currentPush = pushToken
        backend.registerDevice(enrollmentToken: token, pushToken: currentPush, platform: "ios") { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let enrollment):
                    guard let self = self else { return }
                    // Store auth token for authenticated routes
                    self.backend.authToken = enrollment.signedDeviceToken
                    // TODO REMOVE FOR PROD OR ADD DEBUG GUARD
                    print("JWT: \(enrollment.signedDeviceToken ?? "-")")
                    // If APNs token was received earlier (before auth), push it now
                    if let existingPush = self.pushToken, !existingPush.isEmpty {
                        print("🔄 Uploading existing APNs token after auth: \(existingPush)")
                        self.backend.updateAPNSToken(apnsToken: existingPush) { result in
                            switch result {
                            case .success:
                                print("✅ Existing APNs token uploaded after auth")
                            case .failure(let error):
                                print("❌ Failed to upload existing APNs token: \(error)")
                            }
                        }
                    }
                    var newEnrollment = enrollment

                    // De-duplicate overlapping teams across enrollments for the same tenant
                    // Rule: Manager has precedence over Member; do not allow the same team in multiple enrollments
                    // 1) If new is manager: remove overlapping teams from existing member enrollments (and also from other enrollments regardless of role to avoid duplicates)
                    // 2) If new is member: remove overlapping teams that are already managed; if nothing remains, skip adding
                    // Also ensure a team appears only once across all enrollments for a tenant

                    // Compute overlaps and adjust existing enrollments
                    var updatedExisting: [Enrollment] = []
                    for existing in self.enrollments {
                        if existing.tenantId == newEnrollment.tenantId {
                            if newEnrollment.role == .manager {
                                // Replace any existing enrollments for same tenant/email with the new explicit selection
                                if let newEmail = newEnrollment.email, let existingEmail = existing.email, newEmail == existingEmail {
                                    continue // drop existing for same email
                                } else {
                                    // Remove overlapping teams from other enrollments for the same tenant
                                    let remaining = existing.teamIds.filter { !newEnrollment.teamIds.contains($0) }
                                    if !remaining.isEmpty {
                                        let adjusted = Enrollment(
                                            deviceId: existing.deviceId,
                                            deviceToken: existing.deviceToken,
                                            tenantId: existing.tenantId,
                                            tenantName: existing.tenantName,
                                            teamIds: remaining,
                                            email: existing.email,
                                            role: existing.role,
                                            signedDeviceToken: existing.signedDeviceToken
                                        )
                                        updatedExisting.append(adjusted)
                                    }
                                }
                            } else {
                                // Member: avoid duplicating teams
                                let nonOverlapping = existing
                                updatedExisting.append(nonOverlapping)
                                newEnrollment = Enrollment(
                                    deviceId: newEnrollment.deviceId,
                                    deviceToken: newEnrollment.deviceToken,
                                    tenantId: newEnrollment.tenantId,
                                    tenantName: newEnrollment.tenantName,
                                    teamIds: newEnrollment.teamIds.filter { !existing.teamIds.contains($0) },
                                    email: newEnrollment.email,
                                    role: newEnrollment.role,
                                    signedDeviceToken: newEnrollment.signedDeviceToken
                                )
                            }
                        } else {
                            updatedExisting.append(existing)
                        }
                    }

                    self.enrollments = updatedExisting

                    // If after de-dup nothing remains to add, just refresh data and finish
                    if newEnrollment.teamIds.isEmpty {
                        self.appPhase = .registered
                        self.loadUpcomingDiensten()
                        completion(.success(()))
                        return
                    }

                    // Enforce max 5 total followed (tenant, team) pairs
                    let existingPairsCount: Int = self.enrollments.reduce(0) { acc, e in acc + e.teamIds.count }
                    let newCount = newEnrollment.teamIds.count
                    if existingPairsCount + newCount > 5 {
                        completion(.failure(NSError(
                            domain: "AppModel",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "Je kunt maximaal 5 teams volgen. Verwijder eerst een team om verder te gaan."]
                        )))
                        return
                    }

                    if let index = self.enrollments.firstIndex(where: { $0.tenantId == newEnrollment.tenantId && $0.email == newEnrollment.email && $0.role == newEnrollment.role }) {
                        self.enrollments[index] = newEnrollment
                    } else {
                        self.enrollments.append(newEnrollment)
                    }
                    self.appPhase = .registered
                    self.loadUpcomingDiensten()
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func handleCTADeepLink(token: String) {
        pendingAction = .shiftVolunteer(token: token)
    }

    func loadUpcomingDiensten() {
        let currentEnrollments = enrollments
        guard !currentEnrollments.isEmpty else { return }
        upcomingDiensten = []
        let group = DispatchGroup()
        var collected: [Dienst] = []
        for enrollment in currentEnrollments {
            group.enter()
            backend.fetchUpcomingDiensten(tenantId: enrollment.tenantId, teamIds: enrollment.teamIds) { result in
                if case .success(let diensten) = result {
                    collected.append(contentsOf: diensten)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            // Deduplicate by dienst.id, keep the newest (by updated_at, then start_tijd)
            var byId: [String: Dienst] = [:]
            for d in collected {
                if let existing = byId[d.id] {
                    let lhs = d.updated_at
                    let rhs = existing.updated_at
                    let chooseLeft: Bool
                    if let l = lhs, let r = rhs {
                        chooseLeft = l > r
                    } else if lhs != nil && rhs == nil {
                        chooseLeft = true
                    } else if lhs == nil && rhs != nil {
                        chooseLeft = false
                    } else {
                        chooseLeft = d.start_tijd >= existing.start_tijd
                    }
                    if chooseLeft { byId[d.id] = d }
                } else {
                    byId[d.id] = d
                }
            }
            let unique = Array(byId.values)
            // Sort: future first (soonest→latest), then past (most recent past→older)
            let now = Date()
            let future = unique.filter { $0.start_tijd >= now }.sorted { $0.start_tijd < $1.start_tijd }
            let past = unique.filter { $0.start_tijd < now }.sorted { $0.start_tijd > $1.start_tijd }
            self.upcomingDiensten = future + past
            #if DEBUG
            let total = self.upcomingDiensten.count
            print("📦 Loaded diensten: total=\(total)")
            let byTenant = Dictionary(grouping: self.upcomingDiensten, by: { $0.tenant_id })
            for (tenant, items) in byTenant {
                let teams = items.compactMap { $0.team }
                let uniqueTeams = Set(teams.map { ($0.id, $0.code ?? "", $0.pk ?? "", $0.naam) }.map { "id=\($0.0) code=\($0.1) pk=\($0.2) naam=\($0.3)" })
                print("  • tenant=\(tenant) count=\(items.count) teams=[\(uniqueTeams.joined(separator: ", "))]")
            }
            #endif
        }
    }

    func unregister(from dienst: Dienst, completion: @escaping (Result<Void, Error>) -> Void) {
        backend.unregister(tenantId: dienst.tenant_id, teamId: dienst.team?.id, dienstId: dienst.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.upcomingDiensten.removeAll { $0.id == dienst.id }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - New Navigation Functions
    
    func startNewEnrollment() {
        // Reset current onboarding state and go back to QR scanning
        invite = nil
        tenantContext = nil
        verifiedEmail = nil
        appPhase = .onboarding
    }
    
    func validateManagerStatus() {
        // Check if all enrolled managers are still valid
        // This should be called on app startup
        let currentEnrollments = enrollments
        guard !currentEnrollments.isEmpty else { return }
        
        for enrollment in currentEnrollments {
            // Mock validation - in real app would call backend
            print("🔍 Validating manager status for \(enrollment.email ?? "-") at \(enrollment.tenantName)")
            // TODO: Implement real backend validation
            // If validation fails, remove enrollment:
            // self.enrollments.removeAll { $0.deviceId == enrollment.deviceId }
        }
    }
    
    func removeEnrollments(for tenantId: String) {
        // Find the tenant slug for the backend API
        guard let enrollment = enrollments.first(where: { $0.tenantId == tenantId }) else {
            print("⚠️ No enrollment found for tenant \(tenantId)")
            return
        }
        
        // Convert tenant ID to tenant slug for backend API
        // Note: In this app structure, we need to extract the slug from the tenant ID
        // For now, assuming tenantId contains the slug or can be used directly
        let tenantSlug = tenantId
        
        // Call backend API to remove tenant enrollment
        backend.removeTenantEnrollment(tenantSlug) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Successfully removed tenant \(tenantId) from backend")
                    
                    // Update local state after successful backend update
                    self?.updateLocalStateAfterTenantRemoval(tenantId: tenantId)
                    
                case .failure(let error):
                    print("❌ Failed to remove tenant from backend: \(error)")
                    
                    // Fallback: still update local state for offline functionality
                    self?.updateLocalStateAfterTenantRemoval(tenantId: tenantId)
                }
            }
        }
    }
    
    private func updateLocalStateAfterTenantRemoval(tenantId: String) {
        enrollments.removeAll { $0.tenantId == tenantId }
        SecureStorage.shared.storeEnrollments(enrollments)
        
        // Remove related diensten
        upcomingDiensten.removeAll { $0.tenant_id == tenantId }
        
        print("🗑️ Removed all enrollments for tenant: \(tenantId)")
    }
    
    func removeTeam(teamId: String, from tenantId: String) {
        // First find the team code from the enrollment
        guard let enrollment = enrollments.first(where: { $0.tenantId == tenantId }),
              let teamIndex = enrollment.teamIds.firstIndex(of: teamId) else {
            print("⚠️ Team \(teamId) not found in tenant \(tenantId)")
            return
        }
        
        // Convert team ID to team code for backend API
        // Note: In this app, team ID and team code are the same, but this could be enhanced
        let teamCode = teamId
        
        // Call backend API to remove team from enrollment
        backend.removeTeamsFromEnrollment([teamCode]) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Successfully removed team \(teamId) from backend")
                    
                    // Update local state after successful backend update
                    self?.updateLocalStateAfterTeamRemoval(teamId: teamId, tenantId: tenantId)
                    
                case .failure(let error):
                    print("❌ Failed to remove team from backend: \(error)")
                    
                    // Fallback: still update local state for offline functionality
                    self?.updateLocalStateAfterTeamRemoval(teamId: teamId, tenantId: tenantId)
                }
            }
        }
    }
    
    private func updateLocalStateAfterTeamRemoval(teamId: String, tenantId: String) {
        // Remove the specific team from enrollments by creating new enrollment objects
        enrollments = enrollments.compactMap { enrollment in
            if enrollment.tenantId == tenantId {
                let updatedTeamIds = enrollment.teamIds.filter { $0 != teamId }
                // If no teams left, remove the entire enrollment
                if updatedTeamIds.isEmpty {
                    return nil
                }
                // Create new enrollment with updated team list
                return Enrollment(
                    deviceId: enrollment.deviceId,
                    deviceToken: enrollment.deviceToken,
                    tenantId: enrollment.tenantId,
                    tenantName: enrollment.tenantName,
                    teamIds: updatedTeamIds,
                    email: enrollment.email,
                    role: enrollment.role,
                    signedDeviceToken: enrollment.signedDeviceToken
                )
            }
            return enrollment
        }
        
        SecureStorage.shared.storeEnrollments(enrollments)
        
        // Remove related diensten
        upcomingDiensten.removeAll { $0.team?.id == teamId && $0.tenant_id == tenantId }
        
        print("🗑️ Removed team \(teamId) from tenant \(tenantId)")
    }
    
    func navigateToTeam(tenantId: String, teamId: String) {
        // Set deep link navigation for HomeView to handle
        deepLinkNavigation = DeepLinkNavigation(tenantId: tenantId, teamId: teamId)
    }

    // MARK: - Team Selection Helpers
    
    func filterAvailableTeams(_ teams: [Team], for tenantId: String) -> [Team] {
        // Get all currently enrolled team IDs for this tenant
        let enrolledTeamIds = Set(enrollments
            .filter { $0.tenantId == tenantId }
            .flatMap { $0.teamIds }
        )
        
        // Filter out teams that are already enrolled
        return teams.filter { team in
            !enrolledTeamIds.contains(team.id)
        }
    }
    
    func isTeamAlreadyEnrolled(_ teamId: String, in tenantId: String) -> Bool {
        return enrollments
            .filter { $0.tenantId == tenantId }
            .flatMap { $0.teamIds }
            .contains(teamId)
    }

    // MARK: - Roles & Permissions

    func roleFor(tenantId: String, teamId: String) -> EnrollmentRole? {
        // Prefer manager if there are multiple enrollments for the same team
        let matches = enrollments.filter { $0.tenantId == tenantId && $0.teamIds.contains(teamId) }
        if let manager = matches.first(where: { $0.role == .manager }) { return manager.role }
        return matches.first?.role
    }

    // MARK: - Member Enrollment (read-only)

    func registerMember(tenantId: String, tenantName: String, teamIds: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        let currentPush = pushToken
        backend.registerMemberDevice(tenantId: tenantId, tenantName: tenantName, teamIds: teamIds, pushToken: currentPush, platform: "ios") { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let enrollment):
                    guard let self = self else { return }
                    var newEnrollment = enrollment
                    // Avoid duplicating teams already present (manager precedence)
                    for existing in self.enrollments where existing.tenantId == tenantId {
                        let overlap = Set(existing.teamIds).intersection(newEnrollment.teamIds)
                        if !overlap.isEmpty {
                            // Remove overlap from the new member enrollment
                            newEnrollment = Enrollment(
                                deviceId: newEnrollment.deviceId,
                                deviceToken: newEnrollment.deviceToken,
                                tenantId: newEnrollment.tenantId,
                                tenantName: newEnrollment.tenantName,
                                teamIds: newEnrollment.teamIds.filter { !overlap.contains($0) },
                                email: newEnrollment.email,
                                role: newEnrollment.role,
                                signedDeviceToken: newEnrollment.signedDeviceToken
                            )
                        }
                    }
                    // Enforce max 5 total followed teams across all enrollments
                    if !newEnrollment.teamIds.isEmpty {
                        let existingPairsCount: Int = self.enrollments.reduce(0) { acc, e in acc + e.teamIds.count }
                        if existingPairsCount + newEnrollment.teamIds.count > 5 {
                            completion(.failure(NSError(
                                domain: "AppModel",
                                code: -4,
                                userInfo: [NSLocalizedDescriptionKey: "Je kunt maximaal 5 teams volgen. Verwijder eerst een team om verder te gaan."]
                            )))
                            return
                        }
                    }
                    if !newEnrollment.teamIds.isEmpty {
                        self.enrollments.append(newEnrollment)
                    }
                    self.appPhase = .registered
                    self.loadUpcomingDiensten()
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Models for CTA & Dienst

struct Dienst: Identifiable, Equatable, Codable {
    let id: String
    let tenant_id: String
    let team: TeamRef?
    let start_tijd: Date
    let eind_tijd: Date
    let minimum_bemanning: Int
    let status: String
    let locatie_naam: String?
    let aanmeldingen_count: Int?
    let aanmeldingen: [String]? // Volunteer names
    let updated_at: Date?

    struct TeamRef: Codable, Equatable {
        let id: String
        let code: String?
        let naam: String
        let pk: String?
    }
}

enum CTAAction: Equatable {
    case shiftVolunteer(token: String)
}

// MARK: - Deep Link Navigation
struct DeepLinkNavigation: Equatable {
    let tenantId: String
    let teamId: String
}



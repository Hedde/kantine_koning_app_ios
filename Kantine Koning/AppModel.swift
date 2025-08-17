//
//  AppModel.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
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
        let email: String
        let signedDeviceToken: String?
    }

    @Published var appPhase: AppPhase = .launching
    @Published var pushToken: String?
    @Published var enrollments: [Enrollment] = [] {
        didSet {
            SecureStorage.shared.storeEnrollments(enrollments)
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
            appPhase = .registered
            loadUpcomingDiensten()
        } else {
            appPhase = .onboarding
        }
    }

    func setPushToken(_ token: String) {
        pushToken = token
    }

    func resetAll() {
        SecureStorage.shared.clearAll()
        enrollments = []
        invite = nil
        tenantContext = nil
        appPhase = .onboarding
        upcomingDiensten = []
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

        let teamIds = context.selectedTeams.map { $0.id }
        backend.enrollDevice(email: email, tenantId: context.tenantId, teamIds: teamIds) { [weak self] result in
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

    func simulateOpenMagicLink(completion: @escaping (Result<Void, Error>) -> Void) {
        guard case let .enrollmentPending(ctx) = appPhase else {
            completion(.failure(NSError(domain: "AppModel", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not pending enrollment"])));
            return
        }
        let teamIds = ctx.tenantContext.selectedTeams.map { $0.id }
        backend.createSimulatedEnrollmentToken(email: ctx.tenantContext.email, tenantId: ctx.tenantContext.tenantId, tenantName: ctx.tenantContext.tenantName, teamIds: teamIds) { token in
            self.handleEnrollmentDeepLink(token: token, completion: completion)
        }
    }

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
                    if let index = self?.enrollments.firstIndex(where: { $0.tenantId == enrollment.tenantId && $0.email == enrollment.email }) {
                        self?.enrollments[index] = enrollment
                    } else {
                        self?.enrollments.append(enrollment)
                    }
                    self?.appPhase = .registered
                    self?.loadUpcomingDiensten()
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
            self.upcomingDiensten = collected.sorted(by: { $0.start_tijd < $1.start_tijd })
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
            print("🔍 Validating manager status for \(enrollment.email) at \(enrollment.tenantName)")
            // TODO: Implement real backend validation
            // If validation fails, remove enrollment:
            // self.enrollments.removeAll { $0.deviceId == enrollment.deviceId }
        }
    }
    
    func removeEnrollments(for tenantId: String) {
        enrollments.removeAll { $0.tenantId == tenantId }
        SecureStorage.shared.storeEnrollments(enrollments)
        
        // Remove related diensten
        upcomingDiensten.removeAll { $0.tenant_id == tenantId }
        
        print("🗑️ Removed all enrollments for tenant: \(tenantId)")
    }
    
    func removeTeam(teamId: String, from tenantId: String) {
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

    struct TeamRef: Codable, Equatable {
        let id: String
        let code: String?
        let naam: String
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



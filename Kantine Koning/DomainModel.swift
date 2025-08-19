import Foundation

// MARK: - Strong IDs
typealias TenantID = String  // slug
typealias TeamID = String    // code or id from backend

// MARK: - Domain
struct DomainModel: Codable, Equatable {
    struct Tenant: Codable, Equatable, Identifiable {
        var id: TenantID { slug }
        let slug: TenantID
        let name: String
        var teams: [Team]
        var signedDeviceToken: String?
    }

    struct Team: Codable, Equatable, Identifiable {
        let id: TeamID
        let code: String?
        let name: String
        let role: Role
        let email: String?
        let enrolledAt: Date
    }

    enum Role: String, Codable, Equatable { case manager, member }

    var deviceID: String
    var apnsToken: String?
    var tenants: [TenantID: Tenant]
    var createdAt: Date
    var updatedAt: Date

    static var empty: DomainModel {
        let now = Date()
        return DomainModel(deviceID: UUID().uuidString, apnsToken: nil, tenants: [:], createdAt: now, updatedAt: now)
    }

    var isEnrolled: Bool { !tenants.isEmpty }
    var primaryAuthToken: String? {
        // Prefer any manager tenant token, fallback to any token
        if let t = tenants.values.first(where: { $0.teams.contains(where: { $0.role == .manager }) }), let token = t.signedDeviceToken { return token }
        return tenants.values.compactMap { $0.signedDeviceToken }.first
    }

    // MARK: - Mutations (immutable-style)
    func applying(delta: EnrollmentDelta) -> DomainModel {
        var copy = self
        let now = Date()
        var tenant = tenants[delta.tenant.slug] ?? Tenant(slug: delta.tenant.slug, name: delta.tenant.name, teams: [], signedDeviceToken: nil)
        tenant.signedDeviceToken = delta.signedDeviceToken ?? tenant.signedDeviceToken

        // De-duplicate teams across tenants for same team id within this tenant
        let existingIds = Set(tenant.teams.map { $0.id })
        let incoming = delta.teams.filter { !existingIds.contains($0.id) }
        tenant.teams.append(contentsOf: incoming)
        copy.tenants[tenant.slug] = tenant
        copy.updatedAt = now
        return copy
    }

    func removingTenant(_ tenant: TenantID) -> DomainModel {
        var copy = self
        copy.tenants.removeValue(forKey: tenant)
        copy.updatedAt = Date()
        return copy
    }

    func removingTeam(_ team: TeamID, from tenant: TenantID) -> DomainModel {
        var copy = self
        if var t = copy.tenants[tenant] {
            t.teams.removeAll { $0.id == team }
            if t.teams.isEmpty { copy.tenants.removeValue(forKey: tenant) } else { copy.tenants[tenant] = t }
        }
        copy.updatedAt = Date()
        return copy
    }
}

// What we get upon completing enrollment
struct EnrollmentDelta {
    struct TenantInfo { let slug: TenantID; let name: String }
    let tenant: TenantInfo
    let teams: [DomainModel.Team]
    let signedDeviceToken: String?
}

// MARK: - Deep Links
enum DeepLink {
    static func isEnrollment(_ url: URL) -> Bool { (url.scheme == "kantinekoning" && url.host == "device-enroll") || (url.host?.contains("kantinekoning.com") == true && url.path.contains("device-enroll")) }
    static func isCTA(_ url: URL) -> Bool { (url.scheme == "kantinekoning" && url.host == "cta") || (url.host?.contains("kantinekoning.com") == true && url.path.contains("cta")) }
    static func extractToken(from url: URL) -> String? { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" })?.value }
}

// MARK: - Onboarding types
struct EnrollmentContext: Equatable {
    let tenant: TenantID
    let issuedAt: Date
}



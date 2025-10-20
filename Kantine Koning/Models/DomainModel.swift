import Foundation

// MARK: - Strong IDs
typealias TenantID = String  // slug
typealias TeamID = String    // code or id from backend

// MARK: - Domain
struct DomainModel: Codable, Equatable {
    // MARK: - Enrollment tracking for multi-token support
    struct Enrollment: Codable, Equatable, Identifiable {
        let id: String
        let tenantSlug: TenantID
        let teams: [TeamID]  // Team IDs for this enrollment
        let role: Role
        let signedDeviceToken: String
        let enrolledAt: Date
        let email: String?
    }
    
    struct Tenant: Codable, Equatable, Identifiable {
        var id: TenantID { slug }
        let slug: TenantID
        let name: String
        var teams: [Team]
        var signedDeviceToken: String?  // Primary token (backwards compatibility)
        var enrollments: [String] = []  // Enrollment IDs for this tenant
        var seasonEnded: Bool = false  // NEW: Track season state
        var clubLogoUrl: String? = nil  // NEW: Store club logo URL
        
        // Helper to check if tenant is accessible
        var isAccessible: Bool {
            return !seasonEnded && signedDeviceToken != nil
        }
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
    
    struct Banner: Codable, Equatable, Identifiable {
        let id: String
        let tenantSlug: String
        let name: String
        let fileUrl: String
        let linkUrl: String?
        let altText: String?
        let displayOrder: Int
        
        var imageURL: URL? {
            URL(string: fileUrl)
        }
        
        var hasLink: Bool {
            linkUrl != nil && !(linkUrl?.isEmpty ?? true)
        }
    }

    var deviceID: String
    var apnsToken: String?
    var tenants: [TenantID: Tenant]
    var enrollments: [String: Enrollment] = [:]  // enrollmentId -> Enrollment
    var createdAt: Date
    var updatedAt: Date

    static var empty: DomainModel {
        let now = Date()
        return DomainModel(deviceID: UUID().uuidString, apnsToken: nil, tenants: [:], enrollments: [:], createdAt: now, updatedAt: now)
    }

    var isEnrolled: Bool { !tenants.isEmpty }
    
    // Check if we have any active (non-season-ended) tenants
    var hasActiveTenants: Bool { 
        tenants.values.contains { !$0.seasonEnded } 
    }
    
    // Clean up orphaned enrollments that don't belong to any tenant
    mutating func cleanupOrphanedEnrollments() {
        let validEnrollmentIds = Set(tenants.values.flatMap { $0.enrollments })
        let allEnrollmentIds = Set(enrollments.keys)
        let orphanedIds = allEnrollmentIds.subtracting(validEnrollmentIds)
        
        if !orphanedIds.isEmpty {
            for orphanedId in orphanedIds {
                enrollments.removeValue(forKey: orphanedId)
            }
        }
    }
    var primaryAuthToken: String? {
        // Prefer any ACTIVE manager tenant token, fallback to any ACTIVE token
        // Skip season-ended tenants to avoid using revoked tokens
        if let t = tenants.values.first(where: { 
            !$0.seasonEnded && 
            $0.teams.contains(where: { $0.role == .manager }) 
        }), let token = t.signedDeviceToken { 
            Logger.auth("Using active manager token for auth")
            return token 
        }
        if let token = tenants.values
            .filter({ !$0.seasonEnded })
            .compactMap({ $0.signedDeviceToken }).first {
            Logger.auth("Using active member token for auth")
            return token
        }
        Logger.warning("No active auth token available")
        return nil
    }
    
    // MARK: - Token Management
    func authTokenForTeam(_ teamId: TeamID, in tenant: TenantID) -> String? {
        // Check if this tenant has ended season - refuse token if so
        guard let tenantData = tenants[tenant], !tenantData.seasonEnded else {
            Logger.auth("❌ Tenant \(tenant) season ended - refusing token for team \(teamId)")
            return nil
        }
        
        // Find enrollment that contains this team
        // First try direct match (enrollment.teams contains UUIDs)
        let enrollment = enrollments.values.first { enrollment in
            enrollment.tenantSlug == tenant && enrollment.teams.contains(teamId)
        }
        
        if let enrollment = enrollment {
            Logger.auth("✅ Using enrollment-specific token for team \(teamId) in tenant \(tenant)")
            return enrollment.signedDeviceToken
        }
        
        // If no direct match, try to find by team code
        // Find the actual team in this tenant to check its code
        if let actualTeam = tenants[tenant]?.teams.first(where: { $0.id == teamId }),
           let teamCode = actualTeam.code {
            let enrollmentByCode = enrollments.values.first { enrollment in
                enrollment.tenantSlug == tenant && enrollment.teams.contains(teamCode)
            }
            if let enrollmentByCode = enrollmentByCode {
                Logger.auth("✅ Using enrollment-specific token (by code) for team \(teamId) in tenant \(tenant)")
                return enrollmentByCode.signedDeviceToken
            }
        }
        
        // Fallback to tenant token (backwards compatibility)
        Logger.auth("⚠️  Using fallback tenant token for team \(teamId) in tenant \(tenant)")
        return tenants[tenant]?.signedDeviceToken
    }

    // MARK: - Mutations (immutable-style)
    func applying(delta: EnrollmentDelta) -> DomainModel {
        var copy = self
        let now = Date()
        var tenant = tenants[delta.tenant.slug] ?? Tenant(slug: delta.tenant.slug, name: delta.tenant.name, teams: [], signedDeviceToken: nil)
        tenant.signedDeviceToken = delta.signedDeviceToken ?? tenant.signedDeviceToken

        Logger.debug("Applying delta to tenant \(delta.tenant.slug)")
        Logger.debug("Existing teams: \(tenant.teams.count)")
        for team in tenant.teams {
            Logger.debug("Existing team: id=\(team.id) code=\(team.code ?? "nil") name=\(team.name)")
        }
        Logger.debug("Incoming teams: \(delta.teams.count)")
        for team in delta.teams {
            Logger.debug("Incoming team: id=\(team.id) code=\(team.code ?? "nil") name=\(team.name)")
        }

        // De-duplicate teams across tenants for same team id within this tenant
        let existingIds = Set(tenant.teams.map { $0.id })
        let incoming = delta.teams.filter { !existingIds.contains($0.id) }
        Logger.debug("After dedup: \(incoming.count) teams to add")
        tenant.teams.append(contentsOf: incoming)
        
        // Create enrollment record to track this specific token/team combination
        let enrollmentId = UUID().uuidString
        let enrollment = Enrollment(
            id: enrollmentId,
            tenantSlug: delta.tenant.slug,
            teams: delta.teams.map { $0.id },
            role: delta.teams.first?.role ?? .member,
            signedDeviceToken: delta.signedDeviceToken ?? "",
            enrolledAt: now,
            email: delta.teams.first?.email
        )
        
        copy.enrollments[enrollmentId] = enrollment
        tenant.enrollments.append(enrollmentId)
        copy.tenants[tenant.slug] = tenant
        copy.updatedAt = now
        
        Logger.debug("Final tenant teams: \(tenant.teams.count)")
        Logger.debug("Created enrollment \(enrollmentId) with \(delta.teams.count) teams")
        for team in tenant.teams {
            Logger.debug("Final team: id=\(team.id) code=\(team.code ?? "nil") name=\(team.name)")
        }
        
        return copy
    }

    func removingTenant(_ tenant: TenantID) -> DomainModel {
        var copy = self
        
        // Remove all enrollments for this tenant
        if let tenantData = copy.tenants[tenant] {
            for enrollmentId in tenantData.enrollments {
                copy.enrollments.removeValue(forKey: enrollmentId)
            }
        }
        
        copy.tenants.removeValue(forKey: tenant)
        copy.updatedAt = Date()
        return copy
    }

    func removingTeam(_ team: TeamID, from tenant: TenantID) -> DomainModel {
        var copy = self
        if var t = copy.tenants[tenant] {
            t.teams.removeAll { $0.id == team }
            
            // CRITICAL: Also update all enrollments for this tenant to remove this team
            // This prevents stale team IDs in enrollment records which causes reconciliation issues
            for enrollmentId in t.enrollments {
                if var enrollment = copy.enrollments[enrollmentId] {
                    enrollment = Enrollment(
                        id: enrollment.id,
                        tenantSlug: enrollment.tenantSlug,
                        teams: enrollment.teams.filter { $0 != team }, // Remove this team
                        role: enrollment.role,
                        signedDeviceToken: enrollment.signedDeviceToken,
                        enrolledAt: enrollment.enrolledAt,
                        email: enrollment.email
                    )
                    
                    // If enrollment has no teams left, remove it entirely
                    if enrollment.teams.isEmpty {
                        copy.enrollments.removeValue(forKey: enrollmentId)
                        t.enrollments.removeAll { $0 == enrollmentId }
                    } else {
                        copy.enrollments[enrollmentId] = enrollment
                    }
                }
            }
            
            if t.teams.isEmpty { 
                // Remove tenant and all its enrollments
                for enrollmentId in t.enrollments {
                    copy.enrollments.removeValue(forKey: enrollmentId)
                }
                copy.tenants.removeValue(forKey: tenant)
            } else { 
                copy.tenants[tenant] = t 
            }
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
    static func isInvite(_ url: URL) -> Bool { (url.scheme == "kantinekoning" && url.host == "invite") || (url.host?.contains("kantinekoning.com") == true && url.path.contains("invite")) }
    static func extractToken(from url: URL) -> String? { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" })?.value }
    static func extractInviteParams(from url: URL) -> (tenant: String, tenantName: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tenant = components.queryItems?.first(where: { $0.name == "tenant" })?.value,
              let tenantNameRaw = components.queryItems?.first(where: { $0.name == "tenant_name" })?.value else {
            return nil
        }
        // Normalize '+' to spaces for query params, then percent-decode
        let plusNormalized = tenantNameRaw.replacingOccurrences(of: "+", with: " ")
        let tenantName = plusNormalized.removingPercentEncoding ?? plusNormalized
        return (tenant: tenant, tenantName: tenantName)
    }
}

// MARK: - Onboarding types
struct EnrollmentContext: Equatable {
    let tenant: TenantID
    let issuedAt: Date
}



//
//  EnrollmentModels.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 19/08/2025.
//

import Foundation

// MARK: - User Enrollment Domain Models

/// Represents the complete enrollment state for a user device
struct UserEnrollment: Codable, Equatable {
    let deviceID: String
    let deviceToken: String?
    private(set) var tenants: [String: TenantEnrollment]
    let createdAt: Date
    private(set) var updatedAt: Date
    
    // MARK: - Initialization
    
    init(deviceID: String, deviceToken: String?) {
        self.deviceID = deviceID
        self.deviceToken = deviceToken
        self.tenants = [:]
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
    
    private init(deviceID: String, deviceToken: String?, tenants: [String: TenantEnrollment], createdAt: Date, updatedAt: Date) {
        self.deviceID = deviceID
        self.deviceToken = deviceToken
        self.tenants = tenants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    var allTeams: [TeamEnrollment] {
        tenants.values.flatMap(\.teams.values)
    }
    
    var totalTeamCount: Int {
        tenants.values.reduce(0) { $0 + $1.teams.count }
    }
    
    var allTeamIDs: Set<String> {
        Set(tenants.values.flatMap { $0.teams.keys })
    }
    
    var primaryAuthToken: String? {
        // Prefer manager token, fallback to any available token
        let managerTenant = tenants.values.first { tenant in
            tenant.teams.values.contains { $0.role == .manager }
        }
        return managerTenant?.signedDeviceToken ?? tenants.values.first?.signedDeviceToken
    }
    
    var isEmpty: Bool {
        tenants.isEmpty
    }
    
    // MARK: - Query Methods
    
    func teamsForTenant(_ tenantID: String) -> [TeamEnrollment] {
        tenants[tenantID]?.teams.values.sorted { $0.teamName < $1.teamName } ?? []
    }
    
    func isTeamEnrolled(_ teamID: String, in tenantID: String) -> Bool {
        tenants[tenantID]?.teams[teamID] != nil
    }
    
    func tenant(with tenantID: String) -> TenantEnrollment? {
        tenants[tenantID]
    }
    
    func team(with teamID: String, in tenantID: String) -> TeamEnrollment? {
        tenants[tenantID]?.teams[teamID]
    }
    
    // MARK: - Mutation Methods
    
    func addingTenant(_ tenant: TenantEnrollment) -> UserEnrollment {
        var newTenants = tenants
        newTenants[tenant.tenantID] = tenant
        return UserEnrollment(
            deviceID: deviceID,
            deviceToken: deviceToken,
            tenants: newTenants,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
    
    func addingTeam(_ team: TeamEnrollment, to tenantID: String) -> UserEnrollment {
        guard let tenant = tenants[tenantID] else { return self }
        let updatedTenant = tenant.addingTeam(team)
        return addingTenant(updatedTenant)
    }
    
    func removingTeam(with teamID: String, from tenantID: String) -> UserEnrollment {
        guard let tenant = tenants[tenantID] else { return self }
        let updatedTenant = tenant.removingTeam(with: teamID)
        
        var newTenants = tenants
        if updatedTenant.teams.isEmpty {
            // Remove tenant if no teams remain
            newTenants.removeValue(forKey: tenantID)
        } else {
            newTenants[tenantID] = updatedTenant
        }
        
        return UserEnrollment(
            deviceID: deviceID,
            deviceToken: deviceToken,
            tenants: newTenants,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
    
    func removingTenant(with tenantID: String) -> UserEnrollment {
        var newTenants = tenants
        newTenants.removeValue(forKey: tenantID)
        return UserEnrollment(
            deviceID: deviceID,
            deviceToken: deviceToken,
            tenants: newTenants,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

// MARK: - Tenant Enrollment

/// Represents enrollment data for a specific tenant/club
struct TenantEnrollment: Codable, Equatable {
    let tenantID: String
    let tenantName: String
    private(set) var teams: [String: TeamEnrollment]
    let signedDeviceToken: String?
    let enrolledAt: Date
    private(set) var updatedAt: Date
    
    // MARK: - Initialization
    
    init(tenantID: String, tenantName: String, teams: [String: TeamEnrollment] = [:], signedDeviceToken: String?, enrolledAt: Date? = nil) {
        self.tenantID = tenantID
        self.tenantName = tenantName
        self.teams = teams
        self.signedDeviceToken = signedDeviceToken
        let now = Date()
        self.enrolledAt = enrolledAt ?? now
        self.updatedAt = now
    }
    
    private init(tenantID: String, tenantName: String, teams: [String: TeamEnrollment], signedDeviceToken: String?, enrolledAt: Date, updatedAt: Date) {
        self.tenantID = tenantID
        self.tenantName = tenantName
        self.teams = teams
        self.signedDeviceToken = signedDeviceToken
        self.enrolledAt = enrolledAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    var allTeams: [TeamEnrollment] {
        Array(teams.values)
    }
    
    var teamCount: Int {
        teams.count
    }
    
    var managerTeams: [TeamEnrollment] {
        teams.values.filter { $0.role == .manager }
    }
    
    var memberTeams: [TeamEnrollment] {
        teams.values.filter { $0.role == .member }
    }
    
    // MARK: - Mutation Methods
    
    func addingTeam(_ team: TeamEnrollment) -> TenantEnrollment {
        var newTeams = teams
        newTeams[team.teamID] = team
        return TenantEnrollment(
            tenantID: tenantID,
            tenantName: tenantName,
            teams: newTeams,
            signedDeviceToken: signedDeviceToken,
            enrolledAt: enrolledAt,
            updatedAt: Date()
        )
    }
    
    func removingTeam(with teamID: String) -> TenantEnrollment {
        var newTeams = teams
        newTeams.removeValue(forKey: teamID)
        return TenantEnrollment(
            tenantID: tenantID,
            tenantName: tenantName,
            teams: newTeams,
            signedDeviceToken: signedDeviceToken,
            enrolledAt: enrolledAt,
            updatedAt: Date()
        )
    }
}

// MARK: - Team Enrollment

/// Represents enrollment data for a specific team
struct TeamEnrollment: Codable, Equatable, Identifiable {
    let id: String // teamID for Identifiable
    let teamID: String
    let teamCode: String?
    let teamName: String
    let role: AppModel.EnrollmentRole
    let email: String?
    let enrolledAt: Date
    
    init(teamID: String, teamCode: String?, teamName: String, role: AppModel.EnrollmentRole, email: String?, enrolledAt: Date? = nil) {
        self.id = teamID
        self.teamID = teamID
        self.teamCode = teamCode
        self.teamName = teamName
        self.role = role
        self.email = email
        self.enrolledAt = enrolledAt ?? Date()
    }
}

// MARK: - Debug Logging

extension UserEnrollment {
    func logState(_ context: String) {
        print("🔍 [\(context)] UserEnrollment:")
        print("  Device: \(deviceID)")
        print("  Total teams: \(totalTeamCount)")
        print("  Tenants: \(tenants.count)")
        
        for (tenantID, tenant) in tenants {
            print("    📍 \(tenant.tenantName) (\(tenantID))")
            print("       Teams: \(tenant.teamCount)")
            for (_, team) in tenant.teams {
                print("         🏆 \(team.teamName) (\(team.teamID)) - \(team.role.rawValue) - \(team.email ?? "no email")")
            }
        }
    }
    
    static func logOperation(_ operation: String, before: UserEnrollment?, after: UserEnrollment?) {
        print("🔄 Operation: \(operation)")
        before?.logState("BEFORE") ?? print("🔍 [BEFORE] No enrollment")
        after?.logState("AFTER") ?? print("🔍 [AFTER] No enrollment")
    }
}


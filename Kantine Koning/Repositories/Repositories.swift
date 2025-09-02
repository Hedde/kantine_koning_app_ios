import Foundation

// MARK: - Enrollment Repository
protocol EnrollmentRepository {
    func loadModel() -> DomainModel
    func persist(model: DomainModel)
    // NOTE: Auth tokens are now handled per-operation with enrollment-specific tokens
    func requestEnrollment(email: String, tenant: TenantID, teamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void)
    func fetchAllowedTeams(email: String, tenant: TenantID, completion: @escaping (Result<[SearchTeam], Error>) -> Void)
    func registerDevice(enrollmentToken: String, pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void)
    func removeTeams(_ teamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void)
    func removeTenant(_ tenant: TenantID, completion: @escaping (Result<Void, Error>) -> Void)
    func removeAllEnrollments(completion: @escaping (Result<Void, Error>) -> Void)
    func searchTeams(tenant: TenantID, query: String, completion: @escaping (Result<[SearchTeam], Error>) -> Void)
    func registerMember(tenantSlug: String, tenantName: String, teamIds: [TeamID], pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void)
}

final class DefaultEnrollmentRepository: EnrollmentRepository {
    private let storage = UserDefaults.standard
    private let storageKey = "kk_domain_model"
    private let backend: BackendClient

    init(backend: BackendClient = BackendClient()) {
        self.backend = backend
    }

    func loadModel() -> DomainModel {
        if let data = storage.data(forKey: storageKey), let decoded = try? JSONDecoder().decode(DomainModel.self, from: data) {
            return decoded
        }
        return .empty
    }

    func persist(model: DomainModel) {
        if let data = try? JSONEncoder().encode(model) { storage.set(data, forKey: storageKey) }
    }
    
    // NOTE: Auth tokens are now handled per-operation with enrollment-specific tokens

    func requestEnrollment(email: String, tenant: TenantID, teamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        backend.requestEnrollment(email: email, tenantSlug: tenant, teamCodes: teamCodes, completion: completion)
    }

    func fetchAllowedTeams(email: String, tenant: TenantID, completion: @escaping (Result<[SearchTeam], Error>) -> Void) {
        backend.fetchAllowedTeams(email: email, tenantSlug: tenant) { result in
            completion(result.map { list in list.map { SearchTeam(id: $0.id, code: $0.code, name: $0.naam) } })
        }
    }

    func registerDevice(enrollmentToken: String, pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        backend.registerDevice(enrollmentToken: enrollmentToken, pushToken: pushToken, completion: completion)
    }

    func removeTeams(_ teamCodes: [TeamID], completion: @escaping (Result<Void, Error>) -> Void) {
        backend.removeTeams(teamCodes, completion: completion)
    }

    func removeTenant(_ tenant: TenantID, completion: @escaping (Result<Void, Error>) -> Void) {
        backend.removeTenant(tenant, completion: completion)
    }
    
    func removeAllEnrollments(completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.network("Repository calling backend.removeAllEnrollments")
        backend.removeAllEnrollments(completion: completion)
    }

    func searchTeams(tenant: TenantID, query: String, completion: @escaping (Result<[SearchTeam], Error>) -> Void) {
        backend.searchTeams(tenant: tenant, query: query) { result in
            completion(result.map { list in list.map { SearchTeam(id: $0.id, code: $0.code, name: $0.naam) } })
        }
    }

    func registerMember(tenantSlug: String, tenantName: String, teamIds: [TeamID], pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        backend.registerMemberDevice(tenantSlug: tenantSlug, tenantName: tenantName, teamIds: teamIds, pushToken: pushToken, completion: completion)
    }
}

// MARK: - Dienst Repository
protocol DienstRepository {
    // NOTE: Auth tokens are now handled per-operation with enrollment-specific tokens
    func fetchUpcoming(for model: DomainModel, completion: @escaping (Result<[Dienst], Error>) -> Void)
    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void)
    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void)
    func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void)
}

final class DefaultDienstRepository: DienstRepository {
    private let backend: BackendClient
    init(backend: BackendClient = BackendClient()) { self.backend = backend }
    
    // NOTE: Auth tokens are now handled per-operation with enrollment-specific tokens

        func fetchUpcoming(for model: DomainModel, completion: @escaping (Result<[Dienst], Error>) -> Void) {
        // Per-tenant approach: each tenant has its own auth token and team access
        let group = DispatchGroup()
        var collected: [Dienst] = []
        var firstError: Error?
        
        Logger.section("DIENSTEN REFRESH")
        Logger.debug("Fetching diensten for \(model.tenants.count) tenants with separate auth tokens")
        
        for tenant in model.tenants.values {
            group.enter()
            
            // Skip season-ended tenants or get team-specific token
            guard !tenant.seasonEnded else {
                Logger.auth("⏭️ Skipping season-ended tenant \(tenant.slug)")
                group.leave()
                continue
            }
            
            // Use team-specific auth token (safer than direct tenant token)
            guard let firstTeam = tenant.teams.first,
                  let authToken = model.authTokenForTeam(firstTeam.id, in: tenant.slug) else {
                Logger.auth("❌ No valid auth token for tenant \(tenant.slug)")
                group.leave()
                continue
            }
            
            let tenantBackend = BackendClient()
            tenantBackend.authToken = authToken
            
            Logger.network("Fetching diensten for tenant \(tenant.slug) with team-specific token \(authToken.prefix(20))")
            
            tenantBackend.fetchDiensten(tenant: tenant.slug) { [weak self] result in
                switch result {
                case .success(let items):
                    Logger.success("Fetched \(items.count) diensten for tenant \(tenant.slug)")
                    guard let self = self else { 
                        group.leave()
                        return 
                    }
                    let mapped = items.map(self.mapDTOToDienst)
                    collected.append(contentsOf: mapped)
                case .failure(let err):
                    Logger.error("Failed to fetch diensten for tenant \(tenant.slug): \(err)")
                    
                    // Check for token revocation
                    self?.checkTokenRevocation(error: err, tenant: tenant.slug)
                    
                    if firstError == nil { firstError = err }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .global()) {
            if let err = firstError { completion(.failure(err)); return }
            
            Logger.debug("Collected \(collected.count) diensten from all tenants")
            
            // Dedup by id; keep newest by updatedAt then startTime
            var byId: [String: Dienst] = [:]
            for d in collected { 
                if let existing = byId[d.id] {
                    let choose: Bool
                    if let l = d.updatedAt, let r = existing.updatedAt { choose = l > r }
                    else if d.updatedAt != nil { choose = true }
                    else if existing.updatedAt != nil { choose = false }
                    else { choose = d.startTime >= existing.startTime }
                    if choose { byId[d.id] = d }
                } else { 
                    byId[d.id] = d 
                } 
            }
            
            let deduped = Array(byId.values)
            let future = deduped.filter { $0.startTime >= Date() }.sorted { $0.startTime < $1.startTime }
            let past = deduped.filter { $0.startTime < Date() }.sorted { $0.startTime > $1.startTime }
            Logger.success("Final result: \(deduped.count) diensten (\(future.count) future, \(past.count) past)")
            completion(.success(future + past))
        }
    }
    
    // MARK: - Helper Methods
    
    private func deduplicateAndSort(_ diensten: [Dienst]) -> [Dienst] {
        // Dedup by id; keep newest by updatedAt then startTime
        var byId: [String: Dienst] = [:]
        for d in diensten { 
            if let existing = byId[d.id] {
                let choose: Bool
                if let existingUpdated = existing.updatedAt, let dUpdated = d.updatedAt {
                    choose = dUpdated > existingUpdated
                } else {
                    choose = d.startTime > existing.startTime
                }
                if choose { byId[d.id] = d }
            } else {
                byId[d.id] = d
            }
        }
        
        let deduped = Array(byId.values)
        let future = deduped.filter { $0.startTime >= Date() }.sorted { $0.startTime < $1.startTime }
        let past = deduped.filter { $0.startTime < Date() }.sorted { $0.startTime > $1.startTime }
        return future + past
    }
    
    private func mapDTOToDienst(_ dto: DienstDTO) -> Dienst {
        return Dienst(
            id: dto.id,
            tenantId: dto.tenant_id,
            teamId: dto.team?.code ?? dto.team?.id,
            teamName: dto.team?.naam,  // Store team name directly from API
            startTime: dto.start_tijd,
            endTime: dto.eind_tijd,
            status: dto.status,
            locationName: dto.locatie_naam,
            volunteers: dto.aanmeldingen,
            updatedAt: dto.updated_at,
            minimumBemanning: dto.minimum_bemanning
        )
    }

    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
        backend.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { result in
            completion(result.map { dto in
                Dienst(
                    id: dto.id,
                    tenantId: dto.tenant_id,
                    teamId: dto.team?.id,
                    teamName: dto.team?.naam,  // Store team name from add volunteer response
                    startTime: dto.start_tijd,
                    endTime: dto.eind_tijd,
                    status: dto.status,
                    locationName: dto.locatie_naam,
                    volunteers: dto.aanmeldingen,
                    updatedAt: dto.updated_at,
                    minimumBemanning: dto.minimum_bemanning
                )
            })
        }
    }

    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
        backend.removeVolunteer(tenant: tenant, dienstId: dienstId, name: name) { result in
            completion(result.map { dto in
                Dienst(
                    id: dto.id,
                    tenantId: dto.tenant_id,
                    teamId: dto.team?.id,
                    teamName: dto.team?.naam,  // Store team name from remove volunteer response
                    startTime: dto.start_tijd,
                    endTime: dto.eind_tijd,
                    status: dto.status,
                    locationName: dto.locatie_naam,
                    volunteers: dto.aanmeldingen,
                    updatedAt: dto.updated_at,
                    minimumBemanning: dto.minimum_bemanning
                )
            })
        }
    }

    func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        backend.submitVolunteers(actionToken: actionToken, names: names, completion: completion)
    }
}

// MARK: - DTOs used by Dienst repository
struct Dienst: Codable, Identifiable, Equatable {
    let id: String
    let tenantId: TenantID
    let teamId: TeamID?
    let teamName: String?  // Add team name for direct display
    let startTime: Date
    let endTime: Date
    let status: String
    let locationName: String?
    let volunteers: [String]?
    let updatedAt: Date?
    let minimumBemanning: Int
}

// Team search DTO for UI
struct SearchTeam: Identifiable, Equatable {
    let id: String
    let code: String?
    let name: String
}

// Remote Team search DTO
struct TeamDTO: Decodable { let id: String; let code: String?; let naam: String }

// MARK: - DienstRepository Extension for Token Revocation

extension DienstRepository {
    private func checkTokenRevocation(error: Error, tenant: TenantID) {
        // Check if error indicates token revocation
        if let nsError = error as NSError?, 
           nsError.domain == "BackendTokenError",
           let errorType = nsError.userInfo["errorType"] as? String {
            
            switch errorType {
            case "token_revoked":
                let reason = nsError.userInfo["reason"] as? String
                Logger.auth("🚨 Token revoked for tenant \(tenant), reason: \(reason ?? "unknown")")
                
                // Need to notify AppStore about revocation
                NotificationCenter.default.post(
                    name: .tokenRevoked,
                    object: nil,
                    userInfo: ["tenant": tenant, "reason": reason ?? "unknown"]
                )
            default:
                Logger.debug("Other auth error for tenant \(tenant): \(errorType)")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let tokenRevoked = Notification.Name("TokenRevoked")
}



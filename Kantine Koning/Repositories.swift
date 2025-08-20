import Foundation

// MARK: - Enrollment Repository
protocol EnrollmentRepository {
    func loadModel() -> DomainModel
    func persist(model: DomainModel)
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
        print("[Repo] 📡 Repository calling backend.removeAllEnrollments")
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
    func fetchUpcoming(for model: DomainModel, completion: @escaping (Result<[Dienst], Error>) -> Void)
    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void)
    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void)
    func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void)
}

final class DefaultDienstRepository: DienstRepository {
    private let backend: BackendClient
    init(backend: BackendClient = BackendClient()) { self.backend = backend }

    func fetchUpcoming(for model: DomainModel, completion: @escaping (Result<[Dienst], Error>) -> Void) {
        let group = DispatchGroup()
        var collected: [Dienst] = []
        var firstError: Error?
        for tenant in model.tenants.values {
            group.enter()
            backend.fetchDiensten(tenant: tenant.slug) { result in
                switch result {
                case .success(let items):
                    let mapped = items.map { dto in
                        Dienst(
                            id: dto.id,
                            tenantId: dto.tenant_id,
                            teamId: dto.team?.id,
                            startTime: dto.start_tijd,
                            endTime: dto.eind_tijd,
                            status: dto.status,
                            locationName: dto.locatie_naam,
                            volunteers: dto.aanmeldingen,
                            updatedAt: dto.updated_at
                        )
                    }
                    collected.append(contentsOf: mapped)
                case .failure(let err):
                    if firstError == nil { firstError = err }
                }
                group.leave()
            }
        }
        group.notify(queue: .global()) {
            if let err = firstError { completion(.failure(err)); return }
            // Dedup by id; keep newest by updatedAt then startTime
            var byId: [String: Dienst] = [:]
            for d in collected { if let existing = byId[d.id] {
                    let choose: Bool
                    if let l = d.updatedAt, let r = existing.updatedAt { choose = l > r }
                    else if d.updatedAt != nil { choose = true }
                    else if existing.updatedAt != nil { choose = false }
                    else { choose = d.startTime >= existing.startTime }
                    if choose { byId[d.id] = d }
                } else { byId[d.id] = d } }
            let unique = Array(byId.values)
            let now = Date()
            let future = unique.filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }
            let past = unique.filter { $0.startTime < now }.sorted { $0.startTime > $1.startTime }
            completion(.success(future + past))
        }
    }

    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
        backend.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { result in
            completion(result.map { dto in
                Dienst(
                    id: dto.id,
                    tenantId: dto.tenant_id,
                    teamId: dto.team?.id,
                    startTime: dto.start_tijd,
                    endTime: dto.eind_tijd,
                    status: dto.status,
                    locationName: dto.locatie_naam,
                    volunteers: dto.aanmeldingen,
                    updatedAt: dto.updated_at
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
                    startTime: dto.start_tijd,
                    endTime: dto.eind_tijd,
                    status: dto.status,
                    locationName: dto.locatie_naam,
                    volunteers: dto.aanmeldingen,
                    updatedAt: dto.updated_at
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
    let startTime: Date
    let endTime: Date
    let status: String
    let locationName: String?
    let volunteers: [String]?
    let updatedAt: Date?
}

// Team search DTO for UI
struct SearchTeam: Identifiable, Equatable {
    let id: String
    let code: String?
    let name: String
}

// Remote Team search DTO
struct TeamDTO: Decodable { let id: String; let code: String?; let naam: String }



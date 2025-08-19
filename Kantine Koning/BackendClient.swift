import Foundation
import UIKit

final class BackendClient {
    private let baseURL: URL = {
        #if DEBUG
        let defaultURL = "http://localhost:4000"
        #else
        let defaultURL = "https://kantinekoning.com"
        #endif
        let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: override ?? defaultURL)!
    }()

    var authToken: String?

    // MARK: - Enrollment
    func requestEnrollment(email: String, tenantSlug: String, teamCodes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/request"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": email, "tenant_slug": tenantSlug, "team_codes": teamCodes]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            completion(.success(()))
        }.resume()
    }

    func registerDevice(enrollmentToken: String, pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let buildEnvironment: String = {
            #if DEBUG
            return "development"
            #else
            return "production"
            #endif
        }()
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let hardwareId = "\(vendorId):\(bundleId)"
        var body: [String: Any] = [
            "enrollment_token": enrollmentToken,
            "apns_device_token": pushToken ?? "",
            "platform": "ios",
            "build_environment": buildEnvironment,
            "hardware_identifier": hardwareId
        ]
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { body["app_version"] = v }
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String { body["build_number"] = b }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let tenantSlug = obj?["tenant_slug"] as? String ?? "tenant_demo"
                let tenantName = obj?["tenant_name"] as? String ?? "Demo Club"
                let teamCodes = obj?["team_codes"] as? [String] ?? []
                let email = obj?["email"] as? String
                let roleRaw = obj?["role"] as? String ?? "manager"
                let role: DomainModel.Role = roleRaw == "member" ? .member : .manager
                let apiToken = obj?["api_token"] as? String
                self.authToken = apiToken
                let now = Date()
                let teams = teamCodes.map { code in
                    DomainModel.Team(id: code, code: code, name: code, role: role, email: email, enrolledAt: now)
                }
                let delta = EnrollmentDelta(
                    tenant: .init(slug: tenantSlug, name: tenantName),
                    teams: teams,
                    signedDeviceToken: apiToken
                )
                completion(.success(delta))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    func removeTeams(_ teamCodes: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = authToken else { completion(.failure(NSError(domain: "Backend", code: 401))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/remove-teams"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["team_codes": teamCodes])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            completion(.success(()))
        }.resume()
    }

    func removeTenant(_ tenantSlug: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = authToken else { completion(.failure(NSError(domain: "Backend", code: 401))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/tenant"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["tenant_slug": tenantSlug])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            completion(.success(()))
        }.resume()
    }

    // MARK: - APNs
    func updateAPNsToken(_ apns: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !apns.isEmpty else { completion(.success(())); return }
        guard let token = authToken else { completion(.failure(NSError(domain: "Backend", code: -2))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/device/apns-token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let buildEnvironment: String = {
            #if DEBUG
            return "development"
            #else
            return "production"
            #endif
        }()
        var body: [String: Any] = ["apns_device_token": apns, "build_environment": buildEnvironment]
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { body["app_version"] = v }
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String { body["build_number"] = b }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            completion(.success(()))
        }.resume()
    }

    // MARK: - Data
    func fetchDiensten(tenant: TenantID, completion: @escaping (Result<[DienstDTO], Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant), URLQueryItem(name: "past_days", value: "14"), URLQueryItem(name: "future_days", value: "60")]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        let req = URLRequest(url: url)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                struct Resp: Decodable { let diensten: [DienstDTO] }
                let decoder = JSONDecoder()
                let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
                let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                decoder.dateDecodingStrategy = .custom { dec in
                    let c = try dec.singleValueContainer(); let s = try c.decode(String.self)
                    if let d = isoFrac.date(from: s) { return d }
                    if let d = isoNoFrac.date(from: s) { return d }
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
                }
                let resp = try decoder.decode(Resp.self, from: data)
                completion(.success(resp.diensten))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    // MARK: - Volunteers
    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<DienstDTO, Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["naam": name])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                struct Resp: Decodable { let dienst: DienstDTO }
                let decoder = JSONDecoder()
                let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
                let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                decoder.dateDecodingStrategy = .custom { dec in
                    let c = try dec.singleValueContainer(); let s = try c.decode(String.self)
                    if let d = isoFrac.date(from: s) { return d }
                    if let d = isoNoFrac.date(from: s) { return d }
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
                }
                let resp = try decoder.decode(Resp.self, from: data)
                completion(.success(resp.dienst))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<DienstDTO, Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant), URLQueryItem(name: "naam", value: name)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                struct Resp: Decodable { let dienst: DienstDTO }
                let decoder = JSONDecoder()
                let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
                let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                decoder.dateDecodingStrategy = .custom { dec in
                    let c = try dec.singleValueContainer(); let s = try c.decode(String.self)
                    if let d = isoFrac.date(from: s) { return d }
                    if let d = isoNoFrac.date(from: s) { return d }
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
                }
                let resp = try decoder.decode(Resp.self, from: data)
                completion(.success(resp.dienst))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        // If needed later; provide a CTA-specific endpoint mapping
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/cta/shift-volunteer"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": actionToken, "names": names])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            completion(.success(()))
        }.resume()
    }

    // MARK: - Team Search (public)
    func searchTeams(tenant: TenantID, query: String, completion: @escaping (Result<[TeamDTO], Error>) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(.success([])); return }
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/teams/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant), URLQueryItem(name: "q", value: trimmed)]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        let req = URLRequest(url: url)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                struct Resp: Decodable { let teams: [TeamDTO] }
                let resp = try JSONDecoder().decode(Resp.self, from: data)
                completion(.success(resp.teams))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    // MARK: - Member Enrollment (no email)
    func registerMemberDevice(tenantSlug: String, tenantName: String, teamIds: [String], pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        // Simulate or call real endpoint; here mimic backend behavior
        let now = Date()
        let teams = teamIds.map { code in
            DomainModel.Team(id: code, code: code, name: code, role: .member, email: nil, enrolledAt: now)
        }
        let delta = EnrollmentDelta(tenant: .init(slug: tenantSlug, name: tenantName), teams: teams, signedDeviceToken: nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { completion(.success(delta)) }
    }
}

// MARK: - DTOs
struct DienstDTO: Decodable {
    struct TeamRef: Decodable { let id: String; let code: String?; let naam: String; let pk: String? }
    let id: String
    let tenant_id: String
    let team: TeamRef?
    let start_tijd: Date
    let eind_tijd: Date
    let minimum_bemanning: Int
    let status: String
    let locatie_naam: String?
    let aanmeldingen_count: Int?
    let aanmeldingen: [String]?
    let updated_at: Date?
}



import Foundation
import UIKit

final class BackendClient {
    let baseURL: URL = {
        // We testen ALTIJD tegen productie (enige server omgeving)
        // Om push notificaties toch te kunnen testen moet je op productie bij
        // een gebruiker of test tenant bij gebruikers de enrolled Device op APN
        // Sandbox zetten.
        let defaultURL = "https://kantinekoning.com"
        let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let urlString = override ?? defaultURL
        Logger.debug("🌐 Using base URL: \(urlString)")
        return URL(string: urlString)!
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
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                Logger.enrollment("❌ request HTTP error: \(String(describing: (response as? HTTPURLResponse)?.statusCode)) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: body]))); return
            }
            completion(.success(()))
        }.resume()
    }

    // Old flow: fetch allowed teams for manager email before sending magic link
    func fetchAllowedTeams(email: String, tenantSlug: String, completion: @escaping (Result<[TeamDTO], Error>) -> Void) {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/request"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": email, "tenant_slug": tenantSlug, "team_codes": []]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { Logger.enrollment("❌ network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                Logger.enrollment("❌ fetchAllowedTeams HTTP \(http.statusCode) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body]))); return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                Logger.debug("Response keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                
                if let teams = obj?["teams"] as? [[String: Any]] {
                    let mapped: [TeamDTO] = teams.compactMap { t in
                        guard let id = t["id"] as? String else { return nil }
                        let code = t["code"] as? String
                        let naam = t["naam"] as? String ?? code ?? id
                        return TeamDTO(id: id, code: code, naam: naam)
                    }
                    Logger.enrollment("✅ allowed teams count=\(mapped.count)")
                    completion(.success(mapped))
                } else {
                    Logger.warning("teams key missing in response, available keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                    Logger.debug("Full response: \(String(data: data, encoding: .utf8) ?? "<decode failed>")")
                    completion(.success([]))
                }
            } catch { 
                Logger.enrollment("❌ JSON decode error: \(error)")
                completion(.failure(error)) 
            }
        }.resume()
    }

    func registerDevice(enrollmentToken: String, pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        Logger.network("Registering device with token: \(enrollmentToken.prefix(20))...")
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let buildEnvironment: String = {
            #if DEBUG
            return "development"
            #elseif ENABLE_LOGGING
            return "development"  // Release Testing = Sandbox APNs
            #else
            return "production"   // Release = Production APNs
            #endif
        }()
        // Use only the vendor UUID as hardware identifier (backend doesn't need bundle ID)
        let hardwareId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        Logger.debug("🔧 Hardware ID: \(hardwareId)")
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
            if let error = error { Logger.error("network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                Logger.error("HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode)) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                Logger.debug("Response keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                Logger.debug("📄 FULL ENROLLMENT RESPONSE:")
                Logger.debug("\(String(data: data, encoding: .utf8) ?? "<decode failed>")")
                
                // CRITICAL: Validate required fields - no silent fallbacks to demo data
                guard let tenantSlug = obj?["tenant_slug"] as? String, !tenantSlug.isEmpty else {
                    Logger.error("❌ Missing or empty tenant_slug in enrollment response")
                    Logger.error("Response: \(String(data: data, encoding: .utf8) ?? "nil")")
                    completion(.failure(AppError.validationFailed("Missing tenant_slug in API response")))
                    return
                }
                
                guard let tenantName = obj?["tenant_name"] as? String, !tenantName.isEmpty else {
                    Logger.error("❌ Missing or empty tenant_name in enrollment response")
                    Logger.error("Response: \(String(data: data, encoding: .utf8) ?? "nil")")
                    completion(.failure(AppError.validationFailed("Missing tenant_name in API response")))
                    return
                }
                
                let teamCodes = obj?["team_codes"] as? [String] ?? []
                let email = obj?["email"] as? String
                let roleRaw = obj?["role"] as? String ?? "manager"
                let role: DomainModel.Role = roleRaw == "member" ? .member : .manager
                let apiToken = obj?["api_token"] as? String
                
                Logger.debug("Parsed: tenant=\(tenantSlug) name=\(tenantName) teams=\(teamCodes) role=\(role) email=\(email ?? "nil")")
                
                self.authToken = apiToken
                Logger.auth("Set auth token for role=\(role): \(apiToken?.prefix(20) ?? "nil")")
                let now = Date()
                
                // Check if we have team names in response
                let teams: [DomainModel.Team]
                if let teamsArray = obj?["teams"] as? [[String: Any]] {
                    Logger.debug("🏆 Found teams array with \(teamsArray.count) items")
                    teams = teamsArray.compactMap { teamObj in
                        let id = teamObj["id"] as? String ?? ""
                        let code = teamObj["code"] as? String
                        let naam = teamObj["naam"] as? String
                        let name = naam ?? code ?? id  // Prefer naam, fallback to code/id
                        Logger.debug("📝 PARSING Team: id='\(id)' code='\(code ?? "nil")' naam='\(naam ?? "nil")' final_name='\(name)'")
                        guard !id.isEmpty else { return nil }
                        return DomainModel.Team(id: id, code: code, name: name, role: role, email: email, enrolledAt: now)
                    }
                } else {
                    Logger.warning("No teams array in response - backend should include team details")
                    Logger.debug("💡 Backend fix needed: /enrollments/register should return teams array with names")
                    // Create teams with codes as fallback
                    teams = teamCodes.map { code in
                        Logger.debug("  → fallback team code=\(code) (backend should provide name)")
                        return DomainModel.Team(id: code, code: code, name: code, role: role, email: email, enrolledAt: now)
                    }
                }
                
                let delta = EnrollmentDelta(
                    tenant: .init(slug: tenantSlug, name: tenantName),
                    teams: teams,
                    signedDeviceToken: apiToken
                )
                Logger.success("Created delta with \(delta.teams.count) teams")
                completion(.success(delta))
            } catch { 
                Logger.error("JSON decode error: \(error)")
                completion(.failure(error)) 
            }
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
        Logger.debug("🗑️ Removing tenant: \(tenantSlug)")
        guard let token = authToken else { 
            Logger.error("No auth token for tenant removal")
            completion(.failure(NSError(domain: "Backend", code: 401))); return 
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/tenant"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["tenant_slug": tenantSlug])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { Logger.error("removeTenant network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Logger.error("removeTenant HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            Logger.success("Tenant \(tenantSlug) removed successfully")
            completion(.success(()))
        }.resume()
    }
    
    func removeAllEnrollments(completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.debug("🗑️ Removing ALL enrollments")
        guard let token = authToken else { 
            Logger.error("No auth token for removeAll")
            completion(.failure(NSError(domain: "Backend", code: 401))); return 
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/all"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { Logger.error("removeAll network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Logger.error("removeAll HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            Logger.success("All enrollments removed successfully")
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
            #elseif ENABLE_LOGGING
            return "development"  // Release Testing = Sandbox APNs
            #else
            return "production"   // Release = Production APNs
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

    // MARK: - Single Tenant Diensten (Per-enrollment)
    func fetchDiensten(tenant: TenantID, completion: @escaping (Result<[DienstDTO], Error>) -> Void) {
        Logger.network("Fetching diensten for tenant \(tenant)")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tenant", value: tenant), 
            URLQueryItem(name: "future_days", value: "60")
            // past_days removed - use backend default (365 days for full season history)
        ]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        var req = URLRequest(url: url)
        
        // Add auth token - backend will filter by enrolled teams in this specific JWT
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Logger.auth("Using tenant-specific auth token for filtering")
        } else {
            Logger.warning("No auth token - cannot fetch diensten")
            completion(.failure(NSError(domain: "Backend", code: 401)))
            return
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                let userFriendlyError = self.createUserFriendlyError(from: error, context: "diensten")
                completion(.failure(userFriendlyError))
                return 
            }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let userFriendlyError = self.createUserFriendlyError(from: statusCode, data: data ?? Data(), context: "diensten")
                completion(.failure(userFriendlyError))
                return
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
            } catch { 
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor diensten"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }

    // MARK: - All Diensten (Multi-tenant)
    func fetchAllDiensten(completion: @escaping (Result<[DienstDTO], Error>) -> Void) {
        Logger.network("Fetching ALL diensten for all enrolled tenants/teams")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "future_days", value: "60")
            // No tenant parameter = fetch for all enrolled tenants
            // past_days removed - use backend default (365 days for full season history)
        ]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        var req = URLRequest(url: url)
        
        // Add auth token - backend will use device_id to find all enrollments
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Logger.auth("Using authenticated request - backend will find all enrolled teams")
        } else {
            Logger.warning("No auth token - cannot fetch diensten")
            completion(.failure(NSError(domain: "Backend", code: 401)))
            return
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                let userFriendlyError = self.createUserFriendlyError(from: error, context: "diensten")
                completion(.failure(userFriendlyError))
                return 
            }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let userFriendlyError = self.createUserFriendlyError(from: statusCode, data: data ?? Data(), context: "diensten")
                completion(.failure(userFriendlyError))
                return
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
            } catch { 
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor diensten"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }

    // MARK: - Volunteers
    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<DienstDTO, Error>) -> Void) {
        Logger.network("Adding volunteer '\(name)' to dienst \(dienstId) in tenant \(tenant)")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = authToken, !token.isEmpty else {
            Logger.error("No auth token for volunteer add")
            completion(.failure(NSError(domain: "Backend", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authentication token available"])))
            return
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["naam": name])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                Logger.error("addVolunteer network error: \(error)")
                completion(.failure(error)); return 
            }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                Logger.error("addVolunteer HTTP \(statusCode) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: statusCode, userInfo: [NSLocalizedDescriptionKey: body]))); return
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
        Logger.network("Removing volunteer '\(name)' from dienst \(dienstId) in tenant \(tenant)")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant), URLQueryItem(name: "naam", value: name)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        
        guard let token = authToken, !token.isEmpty else {
            Logger.error("No auth token for volunteer remove")
            completion(.failure(NSError(domain: "Backend", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authentication token available"])))
            return
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    // MARK: - Dienst Claiming
    func fetchDienstDetails(dienstId: String, tenantSlug: String, notificationToken: String, completion: @escaping (Result<DienstDTO, Error>) -> Void) {
        Logger.network("Fetching dienst details for \(dienstId)")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        // Build URL with query params
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tenant", value: tenantSlug),
            URLQueryItem(name: "token", value: notificationToken)
        ]
        
        guard let url = comps.url else { 
            completion(.failure(NSError(domain: "Backend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ongeldige URL"])))
            return 
        }
        
        // Auth check - require token for manager access
        guard let token = authToken, !token.isEmpty else {
            Logger.error("No auth token for dienst details fetch")
            completion(.failure(NSError(domain: "Backend", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authenticatie vereist. Log opnieuw in."])))
            return
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("Network error fetching dienst: \(error)")
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geen verbinding met server"])))
                return
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geen response van server"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                Logger.error("Fetch dienst HTTP \(http.statusCode): \(body)")
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
                    let message: String
                    switch http.statusCode {
                    case 404: message = "Dienst niet gevonden"
                    case 403: message = "Geen toegang tot deze dienst"
                    case 409: message = "Deze dienst is al geclaimd"
                    default: message = "Kan dienst niet ophalen (HTTP \(http.statusCode))"
                    }
                    completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                }
                return
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
                Logger.success("✅ Dienst details ophalen succesvol")
                completion(.success(resp.dienst))
            } catch {
                Logger.error("Failed to decode dienst: \(error)")
                completion(.failure(NSError(domain: "Backend", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ongeldig antwoord van server"])))
            }
        }.resume()
    }
    
    func claimDienst(dienstId: String, teamId: String, notificationToken: String, completion: @escaping (Result<DienstDTO, Error>) -> Void) {
        Logger.network("Claiming dienst \(dienstId) for team \(teamId)")
        Logger.auth("Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/claim"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = authToken, !token.isEmpty else {
            Logger.error("No auth token for dienst claim")
            completion(.failure(NSError(domain: "Backend", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authentication token available"])))
            return
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "team_id": teamId,
            "notification_token": notificationToken
        ]
        
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("Network error claiming dienst: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                Logger.error("Claim dienst HTTP \(http.statusCode): \(body)")
                
                // Parse error messages from backend
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                } else {
                    completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                }
                return
            }
            
            do {
                struct Resp: Decodable {
                    let success: Bool
                    let message: String
                    let dienst: DienstDTO
                }
                
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
                Logger.success("✅ Dienst claimed successfully: \(resp.message)")
                completion(.success(resp.dienst))
            } catch {
                Logger.error("Failed to decode claim response: \(error)")
                completion(.failure(error))
            }
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
    
    // MARK: - Tenant Search (public)
    func searchTenants(query: String, completion: @escaping (Result<[TenantSearchResult], Error>) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(.success([])); return }
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/tenants/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        let req = URLRequest(url: url)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                struct Resp: Decodable { let tenants: [TenantSearchResult] }
                let resp = try JSONDecoder().decode(Resp.self, from: data)
                completion(.success(resp.tenants))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    // MARK: - Member Enrollment (no email)
    func registerMemberDevice(tenantSlug: String, tenantName: String, teamIds: [String], pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        Logger.network("Registering member device for tenant=\(tenantSlug) teams=\(teamIds)")
        
        // Create a member enrollment token and register via the same endpoint
        let exp = Int(Date().addingTimeInterval(10 * 60).timeIntervalSince1970)
        let claims: [String: Any] = [
            "tenant_slug": tenantSlug,
            "tenant_name": tenantName,
            "team_codes": teamIds,
            "role": "member",
            "purpose": "device-enroll",
            "exp": exp,
            "jti": UUID().uuidString,
            "max_uses": 1
        ]
        
        guard let json = try? JSONSerialization.data(withJSONObject: claims),
              let token = String(data: json, encoding: .utf8)?.data(using: .utf8)?.base64EncodedString() else {
            completion(.failure(NSError(domain: "Backend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Token creation failed"])))
            return
        }
        
        Logger.debug("🎫 Created member token, calling registerDevice")
        registerDevice(enrollmentToken: token, pushToken: pushToken, completion: completion)
    }

    // MARK: - Tenant Information
    // MARK: - Tenant Info
    
    func fetchTenantInfo(completion: @escaping (Result<TenantInfoResponse, Error>) -> Void) {
        guard let token = authToken else { 
            completion(.failure(NSError(domain: "Backend", code: 401))); return 
        }
        
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/tenants"))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "Backend", code: -1))); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "Backend", code: (response as? HTTPURLResponse)?.statusCode ?? -1))); return
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(TenantInfoResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Leaderboard
    func fetchLeaderboard(tenant: TenantID, period: String = "season", teamId: String? = nil, completion: @escaping (Result<LeaderboardResponse, Error>) -> Void) {
        Logger.leaderboard("Fetching leaderboard for tenant \(tenant) period=\(period) teamId=\(teamId ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/leaderboard"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "tenant", value: tenant),
            URLQueryItem(name: "period", value: period)
        ]
        if let teamId = teamId {
            queryItems.append(URLQueryItem(name: "team_id", value: teamId))
        }
        comps.queryItems = queryItems
        
        guard let url = comps.url else { 
            completion(.failure(NSError(domain: "Backend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return 
        }
        
        var req = URLRequest(url: url)
        
        // Add auth token if available
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Logger.auth("Using authenticated request for leaderboard")
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                Logger.error("leaderboard network error: \(error)")
                let userFriendlyError = self.createUserFriendlyError(from: error, context: "leaderboard")
                completion(.failure(userFriendlyError))
                return 
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                let userError = NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geen antwoord van server ontvangen"])
                completion(.failure(userError))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let userFriendlyError = self.createUserFriendlyError(from: http.statusCode, data: data, context: "leaderboard")
                completion(.failure(userFriendlyError))
                return
            }
            
            do {
                // Log the raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.debug("📄 Raw leaderboard response: \(responseString)")
                }
                
                let decoder = JSONDecoder()
                // Note: Not using .convertFromSnakeCase because we have custom CodingKeys
                let leaderboard = try decoder.decode(LeaderboardResponse.self, from: data)
                Logger.success("Leaderboard fetched: \(leaderboard.teams.count) teams, opt_out=\(leaderboard.tenant.leaderboardOptOut)")
                completion(.success(leaderboard))
            } catch {
                Logger.error("leaderboard decode error: \(error)")
                
                // Log more detailed error info
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.debug("📄 Failed response body: \(responseString)")
                }
                
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor leaderboard"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }
    
    func fetchGlobalLeaderboard(tenant: TenantID, period: String = "season", teamId: String? = nil, completion: @escaping (Result<GlobalLeaderboardResponse, Error>) -> Void) {
        Logger.leaderboard("Fetching global leaderboard for tenant \(tenant) period=\(period) teamId=\(teamId ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/leaderboard/global"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "tenant", value: tenant),
            URLQueryItem(name: "period", value: period)
        ]
        if let teamId = teamId {
            queryItems.append(URLQueryItem(name: "team_id", value: teamId))
        }
        comps.queryItems = queryItems
        
        guard let url = comps.url else { 
            completion(.failure(NSError(domain: "Backend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return 
        }
        
        var req = URLRequest(url: url)
        
        // Add auth token if available
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Logger.auth("Using authenticated request for global leaderboard")
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                Logger.error("global leaderboard network error: \(error)")
                let userFriendlyError = self.createUserFriendlyError(from: error, context: "globale leaderboard")
                completion(.failure(userFriendlyError))
                return 
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                let userError = NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geen antwoord van server ontvangen"])
                completion(.failure(userError))
                return
            }
            
            // Handle forbidden (tenant opted out)
            if http.statusCode == 403 {
                Logger.warning("Tenant opted out of global leaderboard")
                completion(.failure(NSError(domain: "Backend", code: 403, userInfo: [NSLocalizedDescriptionKey: "tenant_opted_out"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let userFriendlyError = self.createUserFriendlyError(from: http.statusCode, data: data, context: "globale leaderboard")
                completion(.failure(userFriendlyError))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                // Note: Manual CodingKeys used instead of .convertFromSnakeCase to avoid conflicts
                let leaderboard = try decoder.decode(GlobalLeaderboardResponse.self, from: data)
                Logger.success("Global leaderboard fetched: \(leaderboard.teams.count) teams")
                completion(.success(leaderboard))
            } catch {
                Logger.error("global leaderboard decode error: \(error)")
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor globale leaderboard"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }
    
    // MARK: - Banners
    func fetchBanners(tenant: TenantID, completion: @escaping (Result<[BannerDTO], Error>) -> Void) {
        Logger.network("Fetching banners for tenant \(tenant)")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/banners"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tenant", value: tenant),
            URLQueryItem(name: "randomize", value: "true")
        ]
        
        guard let url = comps.url else { 
            completion(.failure(NSError(domain: "Backend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return 
        }
        
        var req = URLRequest(url: url)
        
        // Add auth token for device enrollment verification
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Logger.auth("Using authenticated request for banners")
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                let userFriendlyError = self.createUserFriendlyError(from: error, context: "banners")
                completion(.failure(userFriendlyError))
                return 
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                let userError = NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geen antwoord van server ontvangen"])
                completion(.failure(userError))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let userFriendlyError = self.createUserFriendlyError(from: http.statusCode, data: data, context: "banners")
                completion(.failure(userFriendlyError))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(BannerResponse.self, from: data)
                Logger.success("Banners fetched: \(response.banners.count) items for tenant \(tenant)")
                completion(.success(response.banners))
            } catch {
                Logger.error("banners decode error: \(error)")
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor banners"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }
    
    // MARK: - Error Handling Helpers
    private func createUserFriendlyError(from error: Error, context: String) -> NSError {
        let nsError = error as NSError
        
        // Check for common network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return NSError(domain: "Backend", code: nsError.code, userInfo: [
                    NSLocalizedDescriptionKey: "Geen internetverbinding beschikbaar"
                ])
            case NSURLErrorTimedOut:
                return NSError(domain: "Backend", code: nsError.code, userInfo: [
                    NSLocalizedDescriptionKey: "Verbinding met server is verlopen"
                ])
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return NSError(domain: "Backend", code: nsError.code, userInfo: [
                    NSLocalizedDescriptionKey: "Kan geen verbinding maken met de server"
                ])
            case NSURLErrorNetworkConnectionLost:
                return NSError(domain: "Backend", code: nsError.code, userInfo: [
                    NSLocalizedDescriptionKey: "Netwerkverbinding is verbroken"
                ])
            default:
                return NSError(domain: "Backend", code: nsError.code, userInfo: [
                    NSLocalizedDescriptionKey: "Netwerkfout opgetreden bij het laden van \(context)"
                ])
            }
        }
        
        // For other errors, provide a generic message
        return NSError(domain: "Backend", code: nsError.code, userInfo: [
            NSLocalizedDescriptionKey: "Er is een fout opgetreden bij het laden van \(context)"
        ])
    }
    
    private func createUserFriendlyError(from statusCode: Int, data: Data, context: String) -> NSError {
        Logger.error("HTTP \(statusCode) for \(context)")
        
        // Log the raw response for debugging, but don't show it to the user
        if let body = String(data: data, encoding: .utf8) {
            Logger.debug("Response body: \(body)")
        }
        
        // Parse 401 errors for token revocation details (NEW)
        if statusCode == 401 {
            if let backendError = parseBackendError(from: data) {
                return convertBackendErrorToNSError(backendError, context: context)
            }
        }
        
        let userMessage: String
        switch statusCode {
        case 400:
            userMessage = "Ongeldige aanvraag voor \(context)"
        case 401:
            userMessage = "Niet geautoriseerd - probeer opnieuw in te loggen"
        case 403:
            userMessage = "Geen toegang tot \(context)"
        case 404:
            userMessage = "\(context.capitalized) niet gevonden"
        case 422:
            userMessage = "Ongeldige gegevens voor \(context)"
        case 500...599:
            userMessage = "Serverfout bij het laden van \(context) - probeer het later opnieuw"
        default:
            userMessage = "Onbekende fout (\(statusCode)) bij het laden van \(context)"
        }
        
        return NSError(domain: "Backend", code: statusCode, userInfo: [
            NSLocalizedDescriptionKey: userMessage
        ])
    }
    
    // NEW: Parse backend error response for token revocation details
    private func parseBackendError(from data: Data) -> BackendError? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorType = json["error"] as? String else {
            return nil
        }
        
        Logger.auth("Parsed backend error type: \(errorType)")
        
        switch errorType {
        case "token_revoked":
            let reason = json["reason"] as? String
            Logger.auth("Token revoked, reason: \(reason ?? "unknown")")
            return .tokenRevoked(reason: reason)
        case "invalid_token":
            Logger.auth("Token invalid")
            return .tokenInvalid
        default:
            let message = json["message"] as? String
            return .unauthorized(message: message)
        }
    }
    
    // NEW: Convert BackendError to NSError for compatibility
    private func convertBackendErrorToNSError(_ backendError: BackendError, context: String) -> NSError {
        let domain = "BackendTokenError"
        
        switch backendError {
        case .tokenRevoked(let reason):
            return NSError(domain: domain, code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Token ingetrokken",
                "errorType": "token_revoked",
                "reason": reason ?? "unknown",
                "context": context
            ])
        case .tokenInvalid:
            return NSError(domain: domain, code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "Token ongeldig",
                "errorType": "invalid_token",
                "context": context
            ])
        case .unauthorized(let message):
            return NSError(domain: domain, code: 1003, userInfo: [
                NSLocalizedDescriptionKey: message ?? "Niet geautoriseerd",
                "errorType": "unauthorized",
                "context": context
            ])
        default:
            return NSError(domain: "Backend", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Onbekende autorisatiefout"
            ])
        }
    }
}

// MARK: - Error Types
enum BackendError: Error, Equatable {
    case tokenRevoked(reason: String?)
    case tokenInvalid
    case unauthorized(message: String?)
    case networkError(code: Int, message: String)
    case decodingError(String)
    case other(Error)
    
    static func == (lhs: BackendError, rhs: BackendError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenRevoked(let l), .tokenRevoked(let r)): return l == r
        case (.tokenInvalid, .tokenInvalid): return true
        case (.unauthorized(let l), .unauthorized(let r)): return l == r
        case (.networkError(let lc, let lm), .networkError(let rc, let rm)): return lc == rc && lm == rm
        case (.decodingError(let l), .decodingError(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - DTOs
struct DienstDTO: Codable {
    struct TeamRef: Codable { let id: String; let code: String?; let naam: String }
    struct DienstTypeRef: Codable { let naam: String; let icon: String }
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
    let dienst_type: DienstTypeRef?
}

struct TenantInfoResponse: Codable {
    struct TenantData: Codable {
        struct TeamData: Codable {
            let id: String
            let code: String
            let name: String
            let role: String
            
            enum CodingKeys: String, CodingKey {
                case id, code, role
                case name = "naam"
            }
        }
        
        let slug: String
        let name: String
        let clubLogoUrl: String?
        let seasonEnded: Bool
        let teams: [TeamData]
        
        enum CodingKeys: String, CodingKey {
            case slug, teams
            case name = "club_name"
            case clubLogoUrl = "club_logo_url"
            case seasonEnded = "season_ended"
        }
    }
    
    let tenants: [TenantData]
}

struct LeaderboardResponse: Codable {
    struct TenantInfo: Codable {
        let slug: String
        let name: String
        let leaderboardOptOut: Bool
        
        enum CodingKeys: String, CodingKey {
            case slug
            case name = "club_name"
            case leaderboardOptOut = "leaderboard_opt_out"
        }
    }
    
    struct ClubInfo: Codable {
        let name: String
        // logoUrl removed - now handled by /tenants API
        
        enum CodingKeys: String, CodingKey {
            case name = "naam"
        }
    }
    
    struct TeamEntry: Codable {
        struct Team: Codable {
            let id: String
            let name: String
            let code: String?
            
            // Custom decoder to handle both String and Int for id, and naam vs name
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode id as String first, then as Int
                if let idString = try? container.decode(String.self, forKey: .id) {
                    self.id = idString
                } else if let idInt = try? container.decode(Int.self, forKey: .id) {
                    self.id = String(idInt)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.id],
                            debugDescription: "Could not decode id as String or Int"
                        )
                    )
                }
                
                // Handle naam vs name  
                if let naam = try? container.decode(String.self, forKey: .naam) {
                    self.name = naam
                } else if let name = try? container.decode(String.self, forKey: .name) {
                    self.name = name
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.naam],
                            debugDescription: "Could not decode naam or name"
                        )
                    )
                }
                
                self.code = try container.decodeIfPresent(String.self, forKey: .code)
            }
            
            // Custom encoder for Codable conformance
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .naam)  // Always encode as naam
                try container.encodeIfPresent(code, forKey: .code)
            }
            
            private enum CodingKeys: String, CodingKey {
                case id, naam, name, code
            }
        }
        
        let rank: Int
        let team: Team
        let points: Int
        let totalHours: Double
        let recentChange: Int
        let positionChange: Int
        let highlighted: Bool
        
        // Custom decoder to handle the entire TeamEntry
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.rank = try container.decode(Int.self, forKey: .rank)
            self.team = try container.decode(Team.self, forKey: .team)
            self.points = try container.decode(Int.self, forKey: .points)
            self.totalHours = try container.decode(Double.self, forKey: .totalHours)
            self.recentChange = try container.decode(Int.self, forKey: .recentChange)
            self.positionChange = try container.decode(Int.self, forKey: .positionChange)
            
            // Handle highlighted field that can be null/nil
            self.highlighted = try container.decodeIfPresent(Bool.self, forKey: .highlighted) ?? false
        }
        
        private enum CodingKeys: String, CodingKey {
            case rank, team, points
            case totalHours = "total_hours"
            case recentChange = "recent_change"
            case positionChange = "position_change"
            case highlighted
        }
    }
    
    let tenant: TenantInfo
    let club: ClubInfo?
    let period: String
    let teams: [TeamEntry]
}

struct GlobalLeaderboardResponse: Codable {
    struct TeamEntry: Codable {
        struct Team: Codable {
            let id: String
            let name: String
            let code: String?
            
            // Custom decoder to handle both String and Int for id, and naam vs name
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode id as String first, then as Int
                if let idString = try? container.decode(String.self, forKey: .id) {
                    self.id = idString
                } else if let idInt = try? container.decode(Int.self, forKey: .id) {
                    self.id = String(idInt)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.id],
                            debugDescription: "Could not decode id as String or Int"
                        )
                    )
                }
                
                // Handle naam vs name  
                if let naam = try? container.decode(String.self, forKey: .naam) {
                    self.name = naam
                } else if let name = try? container.decode(String.self, forKey: .name) {
                    self.name = name
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.naam],
                            debugDescription: "Could not decode naam or name"
                        )
                    )
                }
                
                self.code = try container.decodeIfPresent(String.self, forKey: .code)
            }
            
            // Custom encoder for Codable conformance
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .naam)  // Always encode as naam
                try container.encodeIfPresent(code, forKey: .code)
            }
            
            private enum CodingKeys: String, CodingKey {
                case id, naam, name, code
            }
        }
        
        struct Club: Codable {
            let name: String
            let slug: String
            let logoUrl: String?
            
            // Custom decoder to handle naam vs name
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Handle naam vs name  
                if let naam = try? container.decode(String.self, forKey: .naam) {
                    self.name = naam
                } else if let name = try? container.decode(String.self, forKey: .name) {
                    self.name = name
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath + [CodingKeys.naam],
                            debugDescription: "Could not decode club naam or name"
                        )
                    )
                }
                
                self.slug = try container.decode(String.self, forKey: .slug)
                self.logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
            }
            
            // Custom encoder for Codable conformance
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .naam)  // Always encode as naam
                try container.encode(slug, forKey: .slug)
                try container.encodeIfPresent(logoUrl, forKey: .logoUrl)
            }
            
            private enum CodingKeys: String, CodingKey {
                case naam, name, slug
                case logoUrl = "logo_url"
            }
        }
        
        let rank: Int
        let team: Team
        let club: Club
        let points: Int
        let totalHours: Double
        let recentChange: Int
        let positionChange: Int
        let highlighted: Bool
        
        // Custom decoder to handle the entire TeamEntry
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.rank = try container.decode(Int.self, forKey: .rank)
            self.team = try container.decode(Team.self, forKey: .team)
            self.club = try container.decode(Club.self, forKey: .club)
            self.points = try container.decode(Int.self, forKey: .points)
            self.totalHours = try container.decode(Double.self, forKey: .totalHours)
            self.recentChange = try container.decode(Int.self, forKey: .recentChange)
            self.positionChange = try container.decode(Int.self, forKey: .positionChange)
            
            // Handle highlighted field that can be null/nil
            self.highlighted = try container.decodeIfPresent(Bool.self, forKey: .highlighted) ?? false
        }
        
        private enum CodingKeys: String, CodingKey {
            case rank, team, club, points, highlighted
            case totalHours = "total_hours"
            case recentChange = "recent_change"
            case positionChange = "position_change"
        }
    }
    
    let period: String
    let teams: [TeamEntry]
}

// MARK: - Banner DTOs
struct BannerResponse: Codable {
    let banners: [BannerDTO]
}

struct BannerDTO: Codable, Identifiable {
    let id: String
    let tenantSlug: String
    let name: String
    let fileUrl: String
    let linkUrl: String?
    let altText: String?
    let displayOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case tenantSlug = "tenant_slug"
        case name
        case fileUrl = "file_url"
        case linkUrl = "link_url"
        case altText = "alt_text"
        case displayOrder = "display_order"
    }
}



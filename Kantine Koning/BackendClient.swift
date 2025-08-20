import Foundation
import UIKit

final class BackendClient {
    internal let baseURL: URL = {
        #if DEBUG
        let defaultURL = "http://localhost:4000"
        #else
        let defaultURL = "https://kantinekoning.com"
        #endif
        let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let urlString = override ?? defaultURL
        print("[Backend] 🌐 Using base URL: \(urlString)")
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
                print("[Enroll] ❌ request HTTP error: \(String(describing: (response as? HTTPURLResponse)?.statusCode)) body=\(body)")
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
            if let error = error { print("[Enroll] ❌ network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("[Enroll] ❌ fetchAllowedTeams HTTP \(http.statusCode) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body]))); return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("[Enroll] 🔍 Response keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                
                if let teams = obj?["teams"] as? [[String: Any]] {
                    let mapped: [TeamDTO] = teams.compactMap { t in
                        guard let naam = t["naam"] as? String else { return nil }
                        let code = t["code"] as? String
                        let id = code ?? naam
                        return TeamDTO(id: id, code: code, naam: naam)
                    }
                    print("[Enroll] ✅ allowed teams count=\(mapped.count)")
                    completion(.success(mapped))
                } else {
                    print("[Enroll] ⚠️ teams key missing in response, available keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                    print("[Enroll] 🔍 Full response: \(String(data: data, encoding: .utf8) ?? "<decode failed>")")
                    completion(.success([]))
                }
            } catch { 
                print("[Enroll] ❌ JSON decode error: \(error)")
                completion(.failure(error)) 
            }
        }.resume()
    }

    func registerDevice(enrollmentToken: String, pushToken: String?, completion: @escaping (Result<EnrollmentDelta, Error>) -> Void) {
        print("[Register] 📡 Registering device with token: \(enrollmentToken.prefix(20))...")
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
        print("[Register] 🔧 Hardware ID: \(hardwareId)")
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
            if let error = error { print("[Register] ❌ network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("[Register] ❌ HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode)) body=\(body)")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("[Register] 🔍 Response keys: \(obj?.keys.joined(separator: ", ") ?? "none")")
                print("[Register] 🔍 Full response: \(String(data: data, encoding: .utf8) ?? "<decode failed>")")
                
                let tenantSlug = obj?["tenant_slug"] as? String ?? "tenant_demo"
                let tenantName = obj?["tenant_name"] as? String ?? "Demo Club"
                let teamCodes = obj?["team_codes"] as? [String] ?? []
                let email = obj?["email"] as? String
                let roleRaw = obj?["role"] as? String ?? "manager"
                let role: DomainModel.Role = roleRaw == "member" ? .member : .manager
                let apiToken = obj?["api_token"] as? String
                
                print("[Register] 📋 Parsed: tenant=\(tenantSlug) name=\(tenantName) teams=\(teamCodes) role=\(role) email=\(email ?? "nil")")
                
                self.authToken = apiToken
                print("[Register] 🔑 Set auth token for role=\(role): \(apiToken?.prefix(20) ?? "nil")")
                let now = Date()
                
                // Check if we have team names in response
                let teams: [DomainModel.Team]
                if let teamsArray = obj?["teams"] as? [[String: Any]] {
                    print("[Register] 🏆 Found teams array with \(teamsArray.count) items")
                    teams = teamsArray.compactMap { teamObj in
                        let id = teamObj["id"] as? String ?? teamObj["code"] as? String ?? ""
                        let code = teamObj["code"] as? String
                        let name = teamObj["naam"] as? String ?? teamObj["name"] as? String ?? code ?? id
                        print("[Register]   → team id=\(id) code=\(code ?? "nil") name=\(name)")
                        guard !id.isEmpty else { return nil }
                        return DomainModel.Team(id: id, code: code, name: name, role: role, email: email, enrolledAt: now)
                    }
                } else {
                    print("[Register] ⚠️ No teams array in response - backend should include team details")
                    print("[Register] 💡 Backend fix needed: /enrollments/register should return teams array with names")
                    // Create teams with codes as fallback
                    teams = teamCodes.map { code in
                        print("[Register]   → fallback team code=\(code) (backend should provide name)")
                        return DomainModel.Team(id: code, code: code, name: code, role: role, email: email, enrolledAt: now)
                    }
                }
                
                let delta = EnrollmentDelta(
                    tenant: .init(slug: tenantSlug, name: tenantName),
                    teams: teams,
                    signedDeviceToken: apiToken
                )
                print("[Register] ✅ Created delta with \(delta.teams.count) teams")
                completion(.success(delta))
            } catch { 
                print("[Register] ❌ JSON decode error: \(error)")
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
        print("[Backend] 🗑️ Removing tenant: \(tenantSlug)")
        guard let token = authToken else { 
            print("[Backend] ❌ No auth token for tenant removal")
            completion(.failure(NSError(domain: "Backend", code: 401))); return 
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/tenant"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["tenant_slug": tenantSlug])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { print("[Backend] ❌ removeTenant network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                print("[Backend] ❌ removeTenant HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            print("[Backend] ✅ Tenant \(tenantSlug) removed successfully")
            completion(.success(()))
        }.resume()
    }
    
    func removeAllEnrollments(completion: @escaping (Result<Void, Error>) -> Void) {
        print("[Backend] 🗑️ Removing ALL enrollments")
        guard let token = authToken else { 
            print("[Backend] ❌ No auth token for removeAll")
            completion(.failure(NSError(domain: "Backend", code: 401))); return 
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/all"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error { print("[Backend] ❌ removeAll network: \(error)"); completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                print("[Backend] ❌ removeAll HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(.failure(NSError(domain: "Backend", code: -1))); return
            }
            print("[Backend] ✅ All enrollments removed successfully")
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

    // MARK: - Single Tenant Diensten (Per-enrollment)
    func fetchDiensten(tenant: TenantID, completion: @escaping (Result<[DienstDTO], Error>) -> Void) {
        print("[Backend] 📡 Fetching diensten for tenant \(tenant)")
        print("[Backend] 🔑 Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tenant", value: tenant), 
            URLQueryItem(name: "past_days", value: "14"), 
            URLQueryItem(name: "future_days", value: "60")
        ]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        var req = URLRequest(url: url)
        
        // Add auth token - backend will filter by enrolled teams in this specific JWT
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("[Backend] 🔑 Using tenant-specific auth token for filtering")
        } else {
            print("[Backend] ⚠️ No auth token - cannot fetch diensten")
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
        print("[Backend] 📡 Fetching ALL diensten for all enrolled tenants/teams")
        print("[Backend] 🔑 Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "past_days", value: "14"), 
            URLQueryItem(name: "future_days", value: "60")
            // No tenant parameter = fetch for all enrolled tenants
        ]
        guard let url = comps.url else { completion(.failure(NSError(domain: "Backend", code: -3))); return }
        var req = URLRequest(url: url)
        
        // Add auth token - backend will use device_id to find all enrollments
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("[Backend] 🔑 Using authenticated request - backend will find all enrolled teams")
        } else {
            print("[Backend] ⚠️ No auth token - cannot fetch diensten")
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
        print("[Backend] 📡 Adding volunteer '\(name)' to dienst \(dienstId) in tenant \(tenant)")
        print("[Backend] 🔑 Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let token = authToken, !token.isEmpty else {
            print("[Backend] ❌ No auth token for volunteer add")
            completion(.failure(NSError(domain: "Backend", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authentication token available"])))
            return
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["naam": name])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                print("[Backend] ❌ addVolunteer network error: \(error)")
                completion(.failure(error)); return 
            }
            guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[Backend] ❌ addVolunteer HTTP \(statusCode) body=\(body)")
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
        print("[Backend] 📡 Removing volunteer '\(name)' from dienst \(dienstId) in tenant \(tenant)")
        print("[Backend] 🔑 Auth token available: \(authToken?.prefix(20) ?? "nil")")
        
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tenant", value: tenant), URLQueryItem(name: "naam", value: name)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        
        guard let token = authToken, !token.isEmpty else {
            print("[Backend] ❌ No auth token for volunteer remove")
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
        print("[MemberRegister] 📡 Registering member device for tenant=\(tenantSlug) teams=\(teamIds)")
        
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
        
        print("[MemberRegister] 🎫 Created member token, calling registerDevice")
        registerDevice(enrollmentToken: token, pushToken: pushToken, completion: completion)
    }

    // MARK: - Tenant Information
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
        print("[Backend] 📊 Fetching leaderboard for tenant \(tenant) period=\(period) teamId=\(teamId ?? "nil")")
        
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
            print("[Backend] 🔑 Using authenticated request for leaderboard")
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                print("[Backend] ❌ leaderboard network error: \(error)")
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
                    print("[Backend] 📄 Raw leaderboard response: \(responseString)")
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let leaderboard = try decoder.decode(LeaderboardResponse.self, from: data)
                print("[Backend] ✅ Leaderboard fetched: \(leaderboard.teams.count) teams, opt_out=\(leaderboard.tenant.leaderboardOptOut)")
                completion(.success(leaderboard))
            } catch {
                print("[Backend] ❌ leaderboard decode error: \(error)")
                
                // Log more detailed error info
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[Backend] 📄 Failed response body: \(responseString)")
                }
                
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor leaderboard"
                ])
                completion(.failure(userError))
            }
        }.resume()
    }
    
    func fetchGlobalLeaderboard(tenant: TenantID, period: String = "season", teamId: String? = nil, completion: @escaping (Result<GlobalLeaderboardResponse, Error>) -> Void) {
        print("[Backend] 🌍 Fetching global leaderboard for tenant \(tenant) period=\(period) teamId=\(teamId ?? "nil")")
        
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
            print("[Backend] 🔑 Using authenticated request for global leaderboard")
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { 
                print("[Backend] ❌ global leaderboard network error: \(error)")
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
                print("[Backend] ⚠️ Tenant opted out of global leaderboard")
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
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let leaderboard = try decoder.decode(GlobalLeaderboardResponse.self, from: data)
                print("[Backend] ✅ Global leaderboard fetched: \(leaderboard.teams.count) teams")
                completion(.success(leaderboard))
            } catch {
                print("[Backend] ❌ global leaderboard decode error: \(error)")
                let userError = NSError(domain: "Backend", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Ongeldig antwoord ontvangen van server voor globale leaderboard"
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
        print("[Backend] ❌ HTTP \(statusCode) for \(context)")
        
        // Log the raw response for debugging, but don't show it to the user
        if let body = String(data: data, encoding: .utf8) {
            print("[Backend] Response body: \(body)")
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

struct TenantInfoResponse: Decodable {
    struct TenantData: Decodable {
        struct TeamData: Decodable {
            let id: String
            let code: String
            let name: String
            let role: String
        }
        
        let slug: String
        let name: String
        let clubLogoUrl: String?
        let teams: [TeamData]
        
        enum CodingKeys: String, CodingKey {
            case slug, name, teams
            case clubLogoUrl = "club_logo_url"
        }
    }
    
    let tenants: [TenantData]
}

struct LeaderboardResponse: Decodable {
    struct TenantInfo: Decodable {
        let slug: String
        let name: String
        let leaderboardOptOut: Bool
        // No custom CodingKeys needed - keyDecodingStrategy handles snake_case conversion
    }
    
    struct ClubInfo: Decodable {
        let name: String
        // logoUrl removed - now handled by /tenants API
    }
    
    struct TeamEntry: Decodable {
        struct Team: Decodable {
            let id: String
            let name: String
            let code: String?
            
            // Custom decoder to handle both String and Int for id
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
                
                self.name = try container.decode(String.self, forKey: .name)
                self.code = try container.decodeIfPresent(String.self, forKey: .code)
            }
            
            private enum CodingKeys: String, CodingKey {
                case id, name, code
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
            case rank, team, points, totalHours, recentChange, positionChange, highlighted
            // No manual mapping needed - keyDecodingStrategy handles snake_case conversion
        }
    }
    
    let tenant: TenantInfo
    let club: ClubInfo?
    let period: String
    let teams: [TeamEntry]
}

struct GlobalLeaderboardResponse: Decodable {
    struct TeamEntry: Decodable {
        struct Team: Decodable {
            let id: String
            let name: String
            let code: String?
            
            // Custom decoder to handle both String and Int for id
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
                
                self.name = try container.decode(String.self, forKey: .name)
                self.code = try container.decodeIfPresent(String.self, forKey: .code)
            }
            
            private enum CodingKeys: String, CodingKey {
                case id, name, code
            }
        }
        
        struct Club: Decodable {
            let name: String
            let slug: String
            // logoUrl removed - now handled by /tenants API
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
            case rank, team, club, points, totalHours, recentChange, positionChange, highlighted
            // No manual mapping needed - keyDecodingStrategy handles snake_case conversion
        }
    }
    
    let period: String
    let teams: [TeamEntry]
}



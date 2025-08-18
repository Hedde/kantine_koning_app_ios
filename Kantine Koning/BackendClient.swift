//
//  BackendClient.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

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
	private let iso8601: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	// Bearer token for authenticated mobile API calls
	var authToken: String?

	// MARK: - Enrollment

	func enrollDevice(email: String, tenantSlug: String, teamCodes: [String], completion: @escaping (Result<[AppModel.Team], Error>) -> Void) {
		let url = baseURL.appendingPathComponent("/api/mobile/v1/enrollments/request")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"email": email,
			"tenant_slug": tenantSlug,
			"team_codes": teamCodes
		]
		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		} catch {
			completion(.failure(error)); return
		}
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))); return
			}
			guard (200..<300).contains(http.statusCode) else {
				let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
				completion(.failure(NSError(domain: "BackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))); return
			}
			var parsed: [AppModel.Team] = []
			if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let teams = obj["teams"] as? [[String: Any]] {
				parsed = teams.compactMap { t in
					let code = t["code"] as? String
					let naam = t["naam"] as? String ?? (code ?? "")
					let id = (code ?? naam)
					if id.isEmpty { return nil }
					return AppModel.Team(id: id, code: code, naam: naam)
				}
			}
			completion(.success(parsed))
		}.resume()
	}

	func createSimulatedEnrollmentToken(email: String, tenantId: String, tenantName: String, teamIds: [String], completion: @escaping (String) -> Void) {
		let payload: [String: Any] = [
			"email": email,
			"tenant_id": tenantId,
			"tenant_name": tenantName,
			"team_ids": teamIds,
			"role": "manager",
			"purpose": "device-enroll",
			"exp": Int(Date().addingTimeInterval(10 * 60).timeIntervalSince1970),
			"jti": UUID().uuidString,
			"max_uses": 1
		]
		let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
		completion(json.base64EncodedString())
	}

	func registerDevice(enrollmentToken: String, pushToken: String?, platform: String, completion: @escaping (Result<AppModel.Enrollment, Error>) -> Void) {
		let url = baseURL.appendingPathComponent("/api/mobile/v1/enrollments/register")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		// Detect build environment based on debug flags
		// Test users will be marked via admin panel to use sandbox regardless
		let buildEnvironment: String = {
			#if DEBUG
			return "development"
			#else
			return "production"
			#endif
		}()
		
		// Get app version info
		let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		
		// Generate hardware-based device identifier for deduplication
		let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
		let bundleId = Bundle.main.bundleIdentifier ?? ""
		let hardwareId = "\(vendorId):\(bundleId)" // Stable across app reinstalls
		
		var body: [String: Any] = [
			"enrollment_token": enrollmentToken,
			"apns_device_token": pushToken ?? "",
			"platform": platform,
			"build_environment": buildEnvironment,
			"hardware_identifier": hardwareId
		]
		
		// Add version info if available
		if let appVersion = appVersion {
			body["app_version"] = appVersion
		}
		if let buildNumber = buildNumber {
			body["build_number"] = buildNumber
		}
		do { request.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { completion(.failure(error)); return }
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))); return
			}
			do {
				let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
				let deviceId = obj?["device_id"] as? String ?? UUID().uuidString
				let tenantId = obj?["tenant_slug"] as? String ?? "tenant_demo"
				let tenantName = obj?["tenant_name"] as? String ?? "Demo Club"
				let teamCodes = obj?["team_codes"] as? [String] ?? []
				let email = obj?["email"] as? String
				let roleRaw = obj?["role"] as? String ?? "manager"
				let role: AppModel.EnrollmentRole = roleRaw == "member" ? .member : .manager
				let enrollment = AppModel.Enrollment(
					deviceId: deviceId,
					deviceToken: pushToken ?? "PUSH_STUB",
					tenantId: tenantId,
					tenantName: tenantName,
					teamIds: teamCodes,
					email: email,
					role: role,
					signedDeviceToken: obj?["api_token"] as? String
				)
				if let signed = obj?["api_token"] as? String { self.authToken = signed }
				// APNs token upload is now handled by AppModel after auth is set
				completion(.success(enrollment))
			} catch {
				completion(.failure(error))
			}
		}.resume()
	}

	// MARK: - Member enrollment (no email)
	func registerMemberDevice(tenantId: String, tenantName: String, teamIds: [String], pushToken: String?, platform: String, completion: @escaping (Result<AppModel.Enrollment, Error>) -> Void) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
			let enrollment = AppModel.Enrollment(
				deviceId: UUID().uuidString,
				deviceToken: pushToken ?? "PUSH_STUB",
				tenantId: tenantId,
				tenantName: tenantName,
				teamIds: teamIds,
				email: nil,
				role: .member,
				signedDeviceToken: nil
			)
			completion(.success(enrollment))
		}
	}

	// MARK: - Data

	func fetchUpcomingDiensten(tenantId: String, teamIds: [String], completion: @escaping (Result<[Dienst], Error>) -> Void) {
		var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [
			URLQueryItem(name: "tenant", value: tenantId),
			URLQueryItem(name: "past_days", value: "14"),
			URLQueryItem(name: "future_days", value: "60")
		]
		guard let url = comps.url else {
			completion(.failure(NSError(domain: "BackendClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))); return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))); return
			}
			guard (200..<300).contains(http.statusCode) else {
				let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
				completion(.failure(NSError(domain: "BackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))); return
			}
			do {
				struct Response: Decodable { let diensten: [Dienst] }
				let decoder = JSONDecoder()
				let isoNoFrac = ISO8601DateFormatter()
				isoNoFrac.formatOptions = [.withInternetDateTime]
				let isoFrac = ISO8601DateFormatter()
				isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
				decoder.dateDecodingStrategy = .custom { dec in
					let c = try dec.singleValueContainer()
					let s = try c.decode(String.self)
					if let d = isoFrac.date(from: s) { return d }
					if let d = isoNoFrac.date(from: s) { return d }
					throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
				}
				let resp = try decoder.decode(Response.self, from: data)
				#if DEBUG
				print("🌐 GET /diensten response count=\(resp.diensten.count)")
				#endif
				completion(.success(resp.diensten))
			} catch {
				#if DEBUG
				print("❌ decode error /diensten: \(error)")
				#endif
				completion(.failure(error))
			}
		}.resume()
	}

	func addVolunteer(tenantId: String, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
		var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [URLQueryItem(name: "tenant", value: tenantId)]
		var request = URLRequest(url: comps.url!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token = authToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
		let body = ["naam": name]
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))); return
			}
			do {
				struct Resp: Decodable { let dienst: Dienst }
				let decoder = JSONDecoder()
				let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
				let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
				decoder.dateDecodingStrategy = .custom { dec in
					let c = try dec.singleValueContainer(); let s = try c.decode(String.self)
					if let d = isoFrac.date(from: s) { return d }
					if let d = isoNoFrac.date(from: s) { return d }
					throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
				}
				let resp = try decoder.decode(Resp.self, from: data)
				completion(.success(resp.dienst))
			} catch { completion(.failure(error)) }
		}.resume()
	}

	func removeVolunteer(tenantId: String, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
		var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/diensten/\(dienstId)/volunteer"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [
			URLQueryItem(name: "tenant", value: tenantId),
			URLQueryItem(name: "naam", value: name)
		]
		var request = URLRequest(url: comps.url!)
		request.httpMethod = "DELETE"
		if let token = authToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))); return
			}
			do {
				struct Resp: Decodable { let dienst: Dienst }
				let decoder = JSONDecoder()
				let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
				let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
				decoder.dateDecodingStrategy = .custom { dec in
					let c = try dec.singleValueContainer(); let s = try c.decode(String.self)
					if let d = isoFrac.date(from: s) { return d }
					if let d = isoNoFrac.date(from: s) { return d }
					throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
				}
				let resp = try decoder.decode(Resp.self, from: data)
				completion(.success(resp.dienst))
			} catch { completion(.failure(error)) }
		}.resume()
	}

	func unregister(tenantId: String, teamId: String?, dienstId: String, completion: @escaping (Result<Void, Error>) -> Void) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
			completion(.success(()))
		}
	}

	// MARK: - CTA

	func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
			completion(.success(()))
		}
	}

	// MARK: - Device helpers
	    func updateAPNSToken(apnsToken: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !apnsToken.isEmpty else { completion(.success(())); return }
                guard let authToken = authToken, !authToken.isEmpty else {
            print("⚠️ No auth token available for APNs upload, skipping...")
            completion(.failure(NSError(domain: "BackendClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "No auth token available"])))
            return
        }

        print("🔄 Uploading APNs token to backend with auth...")
        print("🔍 Using auth token: \(authToken.prefix(50))...")
        let url = baseURL.appendingPathComponent("/api/mobile/v1/device/apns-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        // Include build environment info in APNs token updates too
        let buildEnvironment: String = {
            #if DEBUG
            return "development"
            #else
            return "production"
            #endif
        }()
        
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        
        var body: [String: Any] = [
            "apns_device_token": apnsToken,
            "build_environment": buildEnvironment
        ]
        
        // Add version info if available
        if let appVersion = appVersion {
            body["app_version"] = appVersion
        }
        if let buildNumber = buildNumber {
            body["build_number"] = buildNumber
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { 
                print("❌ APNs upload network error: \(error)")
                completion(.failure(error)); return 
            }
            guard let http = response as? HTTPURLResponse else {
                print("❌ APNs upload: no HTTP response")
                completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No body"
                print("❌ APNs upload HTTP \(http.statusCode): \(body)")
                completion(.failure(NSError(domain: "BackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"]))); return
            }
            print("✅ APNs token uploaded successfully")
            completion(.success(()))
        }.resume()
    }
}

// MARK: - Public search (member autocomplete)
extension BackendClient {
	func searchTeams(tenantId: String, query: String, completion: @escaping (Result<[AppModel.Team], Error>) -> Void) {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			completion(.success([])); return
		}
		var comps = URLComponents(url: baseURL.appendingPathComponent("/api/mobile/v1/teams/search"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [
			URLQueryItem(name: "tenant", value: tenantId),
			URLQueryItem(name: "q", value: trimmed)
		]
		guard let url = comps.url else {
			completion(.failure(NSError(domain: "BackendClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))); return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error { completion(.failure(error)); return }
			guard let http = response as? HTTPURLResponse, let data = data, (200..<300).contains(http.statusCode) else {
				completion(.failure(NSError(domain: "BackendClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))); return
			}
			do {
				struct Resp: Decodable { let teams: [TeamDTO] }
				struct TeamDTO: Decodable { let id: String; let code: String?; let naam: String }
				let resp = try JSONDecoder().decode(Resp.self, from: data)
				let mapped = resp.teams.map { AppModel.Team(id: $0.code ?? $0.naam, code: $0.code, naam: $0.naam) }
				completion(.success(mapped))
			} catch { completion(.failure(error)) }
		}.resume()
	}
}



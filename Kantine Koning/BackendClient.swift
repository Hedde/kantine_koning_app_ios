//
//  BackendClient.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import Foundation

final class BackendClient {
	private let baseURL = URL(string: "https://kantinekoning.com")!
	private let iso8601: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	// MARK: - Enrollment

	func enrollDevice(email: String, tenantId: String, teamIds: [String], completion: @escaping (Result<Void, Error>) -> Void) {
		// Stub: simulate sending magic link email
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
			completion(.success(()))
		}
	}

	func createSimulatedEnrollmentToken(email: String, tenantId: String, tenantName: String, teamIds: [String], completion: @escaping (String) -> Void) {
		let payload: [String: Any] = [
			"email": email,
			"tenant_id": tenantId,
			"tenant_name": tenantName,
			"team_ids": teamIds,
			"purpose": "device-enroll",
			"exp": Int(Date().addingTimeInterval(10 * 60).timeIntervalSince1970),
			"jti": UUID().uuidString,
			"max_uses": 1
		]
		let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
		completion(json.base64EncodedString())
	}

	func registerDevice(enrollmentToken: String, pushToken: String?, platform: String, completion: @escaping (Result<AppModel.Enrollment, Error>) -> Void) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
			let deviceId = UUID().uuidString
			let decoded = Data(base64Encoded: enrollmentToken) ?? Data()
			let claims = (try? JSONSerialization.jsonObject(with: decoded)) as? [String: Any]
					let email = (claims?["email"] as? String) ?? "user@example.com"
		let tenantId = (claims?["tenant_id"] as? String) ?? "tenant_demo"
		let tenantName = (claims?["tenant_name"] as? String) ?? "Demo Club"
		let teamIds = (claims?["team_ids"] as? [String]) ?? ["team_1"]
		let enrollment = AppModel.Enrollment(
			deviceId: deviceId,
			deviceToken: pushToken ?? "PUSH_STUB",
			tenantId: tenantId,
			tenantName: tenantName,
			teamIds: teamIds,
			email: email,
			signedDeviceToken: nil
		)
			completion(.success(enrollment))
		}
	}

	// MARK: - Data

	func fetchUpcomingDiensten(tenantId: String, teamIds: [String], completion: @escaping (Result<[Dienst], Error>) -> Void) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
			let now = Date()
			
			// Mock team data mapping based on actual enrolled teams
			let teamMapping: [String: (code: String, naam: String)] = [
				"team_jo11_3": (code: "JO11-3", naam: "JO11-3"),
				"team_jo8_2jm": (code: "JO8-2JM", naam: "JO8-2JM")
			]
			
			// Mock location names
			let locations = ["Kantine", "Sportcafé", "Hoofdveld", "Veld 2"]
			
			let items: [Dienst] = teamIds.enumerated().flatMap { idx, teamId in
				// Get real team info or fallback to teamId
				let teamInfo = teamMapping[teamId] ?? (code: teamId, naam: teamId)
				let location = locations[idx % locations.count]
				
				// Create more realistic times
				let baseDate = Calendar.current.date(byAdding: .day, value: idx + 1, to: now)!
				let startTime = Calendar.current.date(bySettingHour: 8 + (idx * 2), minute: 0, second: 0, of: baseDate)!
				let endTime = Calendar.current.date(byAdding: .hour, value: 2, to: startTime)!
				
				let nextWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: baseDate)!
				let startTime2 = Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: nextWeekDate)!
				let endTime2 = Calendar.current.date(byAdding: .hour, value: 2, to: startTime2)!
				
				// Mock volunteer data based on team
				let volunteers1: [String] = teamId == "team_jo11_3" ? ["Jan", "Anne"] : ["Piet"]
				let volunteers2: [String] = teamId == "team_jo11_3" ? ["Marie"] : []
				
				return [
					Dienst(
						id: "dienst_\(teamId)_1",
						tenant_id: tenantId,
						team: .init(id: teamId, code: teamInfo.code, naam: teamInfo.naam),
						start_tijd: startTime,
						eind_tijd: endTime,
						minimum_bemanning: 2,
						status: "ingepland",
						locatie_naam: location,
						aanmeldingen_count: volunteers1.count,
						aanmeldingen: volunteers1
					),
					Dienst(
						id: "dienst_\(teamId)_2",
						tenant_id: tenantId,
						team: .init(id: teamId, code: teamInfo.code, naam: teamInfo.naam),
						start_tijd: startTime2,
						eind_tijd: endTime2,
						minimum_bemanning: 3,
						status: "ingepland",
						locatie_naam: location,
						aanmeldingen_count: volunteers2.count,
						aanmeldingen: volunteers2
					)
				]
			}
			completion(.success(items))
		}
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
}



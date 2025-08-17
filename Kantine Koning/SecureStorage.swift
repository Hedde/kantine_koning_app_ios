//
//  SecureStorage.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import Foundation

final class SecureStorage {
	static let shared = SecureStorage()

	private let enrollmentsKey = "kk_enrollments"

	func storeEnrollments(_ enrollments: [AppModel.Enrollment]) {
		do {
			let data = try JSONEncoder().encode(enrollments)
			UserDefaults.standard.set(data, forKey: enrollmentsKey)
		} catch {
			// ignore for stub
		}
	}

	func loadEnrollments() -> [AppModel.Enrollment] {
		guard let data = UserDefaults.standard.data(forKey: enrollmentsKey) else { return [] }
		return (try? JSONDecoder().decode([AppModel.Enrollment].self, from: data)) ?? []
	}

	func clearAll() {
		UserDefaults.standard.removeObject(forKey: enrollmentsKey)
	}
}



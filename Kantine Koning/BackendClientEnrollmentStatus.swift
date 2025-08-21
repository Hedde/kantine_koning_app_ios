import Foundation

// MARK: - Enrollment Status
extension BackendClient {
    func fetchEnrollmentStatus(completion: @escaping (Result<EnrollmentStatusDTO, Error>) -> Void) {
        guard let authToken = authToken else {
            completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token"])))
            return
        }
        
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollments/status"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                print("[EnrollmentStatus] ❌ Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("[EnrollmentStatus] ❌ HTTP error \(http.statusCode): \(body)")
                completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            
            do {
                let enrollmentStatus = try JSONDecoder().decode(EnrollmentStatusDTO.self, from: data)
                print("[EnrollmentStatus] ✅ Loaded enrollment status: teams=\(enrollmentStatus.teamEmailPreferences?.count ?? 0), push=\(enrollmentStatus.pushEnabled ?? false)")
                completion(.success(enrollmentStatus))
            } catch {
                print("[EnrollmentStatus] ❌ JSON decode error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - DTOs
struct EnrollmentStatusDTO: Codable {
    let deviceId: String
    let tenantSlug: String
    let tenantName: String
    let teamCodes: [String]
    let role: String
    let status: String
    let teamEmailPreferences: [String: Bool]?
    let pushEnabled: Bool?
    let hasApnsToken: Bool?
    let lastSeenAt: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case tenantSlug = "tenant_slug"
        case tenantName = "tenant_name"
        case teamCodes = "team_codes"
        case role, status
        case teamEmailPreferences = "team_email_preferences"
        case pushEnabled = "push_enabled"
        case hasApnsToken = "has_apns_token"
        case lastSeenAt = "last_seen_at"
    }
    
    /// Get effective email preference for a specific team
    func getEmailPreference(for teamCode: String) -> Bool {
        // Priority: team-specific preference > DEFAULT: true (for safety)
        if let teamPrefs = teamEmailPreferences,
           let teamPref = teamPrefs[teamCode] {
            return teamPref
        }
        // Default to email enabled for safety (no fallback to global)
        return true
    }
}

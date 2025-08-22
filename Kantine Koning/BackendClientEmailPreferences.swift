import Foundation

// MARK: - Email Notification Preferences
extension BackendClient {
    /// Update email preferences for a specific team
    func updateEmailNotificationPreferences(enabled: Bool, teamCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let authToken = authToken else {
            completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token"])))
            return
        }
        
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollment/email-preferences"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "email_notifications_enabled": enabled,
            "team_code": teamCode
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                Logger.error("Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                Logger.error("HTTP error \(http.statusCode): \(body)")
                completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            
            let teamInfo = " for team \(teamCode)"
            Logger.success("Email preferences updated\(teamInfo): \(enabled)")
            completion(.success(()))
        }.resume()
    }
}

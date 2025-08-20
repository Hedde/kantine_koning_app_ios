import Foundation

// MARK: - Email Notification Preferences
extension BackendClient {
    func updateEmailNotificationPreferences(enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let authToken = authToken else {
            completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth token"])))
            return
        }
        
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/mobile/v1/enrollment/email-preferences"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["email_notifications_enabled": enabled]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                print("[EmailPrefs] ❌ Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "Backend", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("[EmailPrefs] ❌ HTTP error \(http.statusCode): \(body)")
                completion(.failure(NSError(domain: "Backend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            
            print("[EmailPrefs] ✅ Email preferences updated: \(enabled)")
            completion(.success(()))
        }.resume()
    }
}

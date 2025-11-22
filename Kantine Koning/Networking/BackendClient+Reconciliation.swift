import Foundation

extension BackendClient {
    /// Sync enrollments to backend for reconciliation.
    ///
    /// This method sends the app's current enrollment state to the backend, which compares it
    /// with its own database and removes orphaned enrollments (teams/enrollments that exist in
    /// backend but not in app).
    ///
    /// - Parameter enrollments: List of current enrollments from the app
    /// - Returns: Summary of cleanup actions performed by backend
    /// - Throws: Error if request fails or response is invalid
    func syncEnrollments(_ enrollments: [EnrollmentSyncData]) async throws -> ReconciliationSummary {
        // Build request payload
        let payload: [String: Any] = [
            "enrollments": enrollments.map { enrollment in
                var dict: [String: Any] = [
                    "tenant_slug": enrollment.tenantSlug,
                    "role": enrollment.role,
                    "team_codes": enrollment.teamCodes
                ]
                
                // Add optional fields based on role
                if let email = enrollment.teamManagerEmail, !email.isEmpty {
                    dict["team_manager_email"] = email
                }
                
                if let hardware = enrollment.hardwareIdentifier, !hardware.isEmpty {
                    dict["hardware_identifier"] = hardware
                }
                
                // Add app version info for debugging (optional, backward compatible)
                if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    dict["app_version"] = v
                }
                if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    dict["build_number"] = b
                }
                
                return dict
            }
        ]
        
        // Create request
        let url = baseURL.appendingPathComponent("/api/mobile/v1/enrollments/sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token (device JWT)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            Logger.network("⚠️ No auth token for sync enrollments")
            throw NSError(domain: "Backend", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No auth token available"
            ])
        }
        
        // Serialize payload
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        Logger.network("📤 POST /enrollments/sync with \(enrollments.count) enrollment(s)")
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.network("❌ Invalid response type")
            throw NSError(domain: "Backend", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response type"
            ])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            Logger.network("❌ HTTP \(httpResponse.statusCode)")
            
            throw NSError(domain: "Backend", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"
            ])
        }
        
        // Parse response
        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summaryDict = responseDict["cleanup_summary"] as? [String: Any] else {
            Logger.network("❌ Invalid response format")
            throw NSError(domain: "Backend", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response format"
            ])
        }
        
        let summary = ReconciliationSummary(
            teamsRemoved: summaryDict["teams_removed"] as? Int ?? 0,
            enrollmentsRevoked: summaryDict["enrollments_revoked"] as? Int ?? 0,
            tenantsAffected: summaryDict["tenants_affected"] as? [String] ?? []
        )
        
        Logger.network("✅ Sync completed: \(summary.enrollmentsRevoked) revoked, \(summary.teamsRemoved) teams removed")
        
        return summary
    }
}


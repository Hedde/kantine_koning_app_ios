import Foundation

/// Service that reconciles enrollment state between app and backend.
///
/// This service handles the "garbage collection" of backend enrollments that were removed
/// in the app but the deletion API call failed. It periodically syncs the app's current
/// enrollment state to the backend, which then cleans up orphaned enrollments.
actor EnrollmentReconciliationService {
    private let backendClient: BackendClient
    
    // Throttling state to prevent excessive sync calls
    private var lastSyncDate: Date?
    private let minimumSyncInterval: TimeInterval = 3600 // 1 hour
    
    init(backendClient: BackendClient) {
        self.backendClient = backendClient
    }
    
    /// Reconcile enrollments with backend if needed (with throttling).
    ///
    /// This method checks if enough time has passed since the last sync before proceeding.
    /// Skips sync if called within the minimum interval (1 hour by default).
    func reconcileIfNeeded(model: DomainModel, hardwareIdentifier: String?, authToken: String?) async {
        // Check throttling
        if let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < minimumSyncInterval {
            let elapsed = Int(Date().timeIntervalSince(lastSync))
            Logger.info("⏭️ Skipping reconciliation - last sync was \(elapsed)s ago (minimum: \(Int(minimumSyncInterval))s)")
            return
        }
        
        await reconcile(model: model, hardwareIdentifier: hardwareIdentifier, authToken: authToken)
    }
    
    /// Force reconciliation (bypass throttling).
    ///
    /// This method always performs reconciliation regardless of when the last sync occurred.
    /// Use this when you need to ensure sync happens (e.g., after major enrollment changes).
    func reconcile(model: DomainModel, hardwareIdentifier: String?, authToken: String?) async {
        Logger.info("🔄 Starting enrollment reconciliation")
        
        // Check if we have an auth token
        guard let token = authToken else {
            Logger.warning("⚠️ No auth token available for reconciliation - skipping")
            return
        }
        
        // Set auth token on backend client
        backendClient.authToken = token
        
        // Build enrollment list from current app state
        // Returns nil if data is incomplete (e.g. team code mapping failed)
        guard let appEnrollments = buildEnrollmentList(from: model, hardwareIdentifier: hardwareIdentifier) else {
            Logger.error("🚨 Reconciliation ABORTED: Incomplete data detected (team code mapping failed)")
            Logger.error("   This is a safety measure to prevent accidental enrollment revokes")
            Logger.error("   Will retry on next app activation when data is complete")
            return
        }
        
        if appEnrollments.isEmpty {
            Logger.info("📭 No active enrollments to sync (app is empty)")
        } else {
            Logger.info("📤 Syncing \(appEnrollments.count) enrollment(s) to backend")
        }
        
        do {
            let summary = try await backendClient.syncEnrollments(appEnrollments)
            
            // Update last sync timestamp on success
            lastSyncDate = Date()
            
            if summary.enrollmentsRevoked == 0 && summary.teamsRemoved == 0 {
                Logger.info("✅ Reconciliation completed - no cleanup needed")
            } else {
                Logger.info("""
                ✅ Reconciliation completed with cleanup:
                   - Teams removed: \(summary.teamsRemoved)
                   - Enrollments revoked: \(summary.enrollmentsRevoked)
                   - Tenants affected: \(summary.tenantsAffected.joined(separator: ", "))
                """)
                
                // Log warning if significant cleanup happened (might indicate issues)
                if summary.enrollmentsRevoked > 0 || summary.teamsRemoved > 3 {
                    Logger.warning("⚠️ Significant cleanup detected - this might indicate failed deletion API calls")
                }
            }
            
        } catch {
            Logger.error("❌ Reconciliation failed: \(error)")
            // Don't update lastSyncDate on failure - will retry next launch
        }
    }
    
    /// Build enrollment sync data from domain model.
    ///
    /// This method extracts all active enrollments from the app's domain model
    /// and converts them to the format expected by the backend API.
    ///
    /// - Parameters:
    ///   - model: The app's current domain model
    ///   - hardwareIdentifier: Device hardware identifier (from UIDevice.current.identifierForVendor)
    /// - Returns: Array of enrollment sync data structures
    private func buildEnrollmentList(from model: DomainModel, hardwareIdentifier: String?) -> [EnrollmentSyncData]? {
        var enrollments: [EnrollmentSyncData] = []
        var hasIncompleteMappings = false
        
        for (tenantSlug, tenant) in model.tenants {
            // Skip tenants with ended seasons - their enrollments are already revoked
            guard !tenant.seasonEnded else {
                Logger.debug("⏭️ Skipping tenant \(tenantSlug): season ended")
                continue
            }
            
            // Process each enrollment for this tenant
            for enrollmentId in tenant.enrollments {
                guard let enrollment = model.enrollments[enrollmentId] else {
                    Logger.warning("⚠️ Enrollment \(enrollmentId) not found in model")
                    continue
                }
                
                // Map team IDs to team codes (backend expects codes, not UUIDs)
                // CRITICAL: All team IDs MUST successfully map to codes
                var teamCodes: [String] = []
                
                for teamId in enrollment.teams {
                    if let code = tenant.teams.first(where: { $0.id == teamId })?.code {
                        teamCodes.append(code)
                    } else {
                        // CRITICAL: Team code lookup failed - data is incomplete!
                        Logger.error("🚨 CRITICAL: No team code found for ID \(teamId) in tenant \(tenantSlug)")
                        Logger.error("   This indicates incomplete tenant.teams data - ABORTING reconciliation to prevent accidental revokes")
                        hasIncompleteMappings = true
                        break
                    }
                }
                
                // If we had mapping failures, abort entire reconciliation
                if hasIncompleteMappings {
                    break
                }
                
                // Skip only if enrollment has NO teams at all (should never happen)
                guard !teamCodes.isEmpty else {
                    Logger.warning("⚠️ Enrollment \(enrollmentId) has no teams - skipping")
                    continue
                }
                
                // Convert enrollment to sync data format
                let syncData = EnrollmentSyncData(
                    tenantSlug: tenantSlug,
                    role: enrollment.role == .manager ? "manager" : "member",
                    teamManagerEmail: enrollment.email,
                    hardwareIdentifier: hardwareIdentifier,
                    teamCodes: teamCodes
                )
                
                enrollments.append(syncData)
            }
            
            // Break outer loop if we had mapping failures
            if hasIncompleteMappings {
                break
            }
        }
        
        // Return nil if data was incomplete (signals reconciliation should be skipped)
        if hasIncompleteMappings {
            return nil
        }
        
        return enrollments
    }
}

// MARK: - Data Structures

/// Enrollment data structure for sync API.
///
/// This matches the backend's expected format for the `/api/mobile/v1/enrollments/sync` endpoint.
struct EnrollmentSyncData: Encodable {
    let tenantSlug: String
    let role: String // "manager" or "member"
    let teamManagerEmail: String?
    let hardwareIdentifier: String?
    let teamCodes: [String]
    
    enum CodingKeys: String, CodingKey {
        case tenantSlug = "tenant_slug"
        case role
        case teamManagerEmail = "team_manager_email"
        case hardwareIdentifier = "hardware_identifier"
        case teamCodes = "team_codes"
    }
}

/// Summary of reconciliation cleanup actions.
///
/// Returned by the backend after reconciliation to indicate what was cleaned up.
struct ReconciliationSummary: Decodable {
    let teamsRemoved: Int
    let enrollmentsRevoked: Int
    let tenantsAffected: [String]
    
    enum CodingKeys: String, CodingKey {
        case teamsRemoved = "teams_removed"
        case enrollmentsRevoked = "enrollments_revoked"
        case tenantsAffected = "tenants_affected"
    }
}


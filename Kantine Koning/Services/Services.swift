import Foundation
import UserNotifications
import UIKit

protocol PushService {
    func requestAuthorization()
    func updateAPNs(token: String, auth: String?)
    // NOTE: setAuthToken removed - auth is now per-operation in updateAPNs
}

final class DefaultPushService: PushService {
    private let backend: BackendClient
    private var lastTokenUpdate: Date?
    private var lastSuccessfulToken: String?
    
    init(backend: BackendClient = BackendClient()) { self.backend = backend }
    
    func requestAuthorization() {
        Logger.push("🔔 Requesting push notification authorization")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                Logger.push("✅ Push notifications authorized - registering for remote notifications")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                Logger.push("❌ Push notifications denied: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }

    func updateAPNs(token: String, auth: String?) {
        let tokenPreview = String(token.prefix(20)) + "..."
        let buildEnvironment = getBuildEnvironment()
        
        // Check if this is a fresh token update
        let isNewToken = lastSuccessfulToken != token
        let timeSinceLastUpdate = lastTokenUpdate?.timeIntervalSinceNow.magnitude ?? Double.infinity
        
        Logger.push("🔄 APNS Token Update Request")
        Logger.push("  → Token: \(tokenPreview)")
        Logger.push("  → Build Environment: \(buildEnvironment)")
        Logger.push("  → Is New Token: \(isNewToken)")
        Logger.push("  → Time Since Last Update: \(String(format: "%.1f", timeSinceLastUpdate))s")
        Logger.push("  → Has Auth: \(auth != nil)")
        
        guard let authToken = auth, !authToken.isEmpty else {
            Logger.push("❌ APNS update skipped - no auth token provided")
            return
        }
        
        lastTokenUpdate = Date()
        backend.authToken = authToken
        Logger.push("  → Using auth token: \(String(authToken.prefix(20)))...")
        
        backend.updateAPNsToken(token) { [weak self] result in
            let duration = Date().timeIntervalSince(self?.lastTokenUpdate ?? Date())
            
            switch result {
            case .success():
                self?.lastSuccessfulToken = token
                Logger.push("✅ APNS token update SUCCESS (took \(String(format: "%.2f", duration))s)")
                Logger.push("  → Environment: \(buildEnvironment)")
                Logger.push("  → Token cached for future comparisons")
                
            case .failure(let error):
                Logger.push("❌ APNS token update FAILED (took \(String(format: "%.2f", duration))s)")
                Logger.push("  → Environment: \(buildEnvironment)")
                Logger.push("  → Error: \(error.localizedDescription)")
                Logger.push("  → Token: \(tokenPreview)")
                
                // Log additional context for debugging
                if let nsError = error as NSError? {
                    Logger.push("  → Error Domain: \(nsError.domain)")
                    Logger.push("  → Error Code: \(nsError.code)")
                }
            }
        }
    }
    
    private func getBuildEnvironment() -> String {
        #if DEBUG
        return "development (sandbox)"
        #elseif ENABLE_LOGGING
        return "testing (sandbox)"
        #else
        return "production"
        #endif
    }
    
    // NOTE: setAuthToken removed - auth is now per-operation via updateAPNs parameter
}



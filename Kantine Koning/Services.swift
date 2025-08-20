import Foundation
import UserNotifications
import UIKit

protocol PushService {
    func requestAuthorization()
    func updateAPNs(token: String, auth: String?)
}

final class DefaultPushService: PushService {
    private let backend: BackendClient
    init(backend: BackendClient = BackendClient()) { self.backend = backend }
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    func updateAPNs(token: String, auth: String?) {
        guard let auth = auth, !auth.isEmpty else { return }
        backend.authToken = auth
        backend.updateAPNsToken(token) { result in
            if case .failure(let err) = result { print("APNs upload failed: \(err)") }
        }
    }
}



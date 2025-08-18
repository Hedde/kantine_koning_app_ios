//
//  AppDelegate.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import UIKit
import UserNotifications

extension Notification.Name {
	static let pushTokenUpdated = Notification.Name("kk_pushTokenUpdated")
	static let incomingURL = Notification.Name("kk_incomingURL")
	static let pushPermissionGranted = Notification.Name("kk_pushPermissionGranted")
	static let pushPermissionDenied = Notification.Name("kk_pushPermissionDenied")
	static let pushPermissionStatusChecked = Notification.Name("kk_pushPermissionStatusChecked")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		UNUserNotificationCenter.current().delegate = self
		// Auto-prompt for notifications on first launch; register if already authorized
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			DispatchQueue.main.async {
				switch settings.authorizationStatus {
				case .notDetermined:
					self.requestPushAuthorization()
				case .authorized, .provisional, .ephemeral:
					UIApplication.shared.registerForRemoteNotifications()
				default:
					break
				}
			}
		}
		return true
	}

	func requestPushAuthorization() {
		print("🔔 Requesting push authorization...")
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
			DispatchQueue.main.async {
				print("🔔 Push authorization result: \(granted ? "✅ GRANTED" : "❌ DENIED")")
				if granted {
					print("🔔 Registering for remote notifications...")
					UIApplication.shared.registerForRemoteNotifications()
					NotificationCenter.default.post(name: .pushPermissionGranted, object: nil)
				} else {
					NotificationCenter.default.post(name: .pushPermissionDenied, object: nil)
				}
			}
		}
	}
	
	func checkNotificationPermissionStatus() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			DispatchQueue.main.async {
				NotificationCenter.default.post(name: .pushPermissionStatusChecked, object: settings.authorizationStatus)
			}
		}
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
		print("📱 APNs Token: \(token)")
		NotificationCenter.default.post(name: .pushTokenUpdated, object: token)
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		print("❌ APNs Registration Failed: \(error)")
	}

    // Handle custom URL scheme: kantinekoning://...
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        NotificationCenter.default.post(name: .incomingURL, object: url)
        return true
    }



	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo = response.notification.request.content.userInfo
		if let linkString = userInfo["deeplink"] as? String, let url = URL(string: linkString) {
			NotificationCenter.default.post(name: .incomingURL, object: url)
		}
		completionHandler()
	}
}

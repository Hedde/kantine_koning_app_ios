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
		// Let the app show an in-app explanation before requesting permission
		// Call requestPushAuthorization() from a user action (e.g., CTA in onboarding/settings)
		return true
	}

	func requestPushAuthorization() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
			DispatchQueue.main.async {
				if granted {
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
		NotificationCenter.default.post(name: .pushTokenUpdated, object: token)
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		// noop for stub
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

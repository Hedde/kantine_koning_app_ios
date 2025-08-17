//
//  AppDelegate.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import UIKit
import UserNotifications

extension Notification.Name {
    static let pushTokenUpdated = Notification.Name("kk_pushTokenUpdated")
    static let incomingURL = Notification.Name("kk_incomingURL")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .pushTokenUpdated, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No-op in stub
    }

    // Universal links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            NotificationCenter.default.post(name: .incomingURL, object: url)
            return true
        }
        return false
    }

    // Push notification tap with deep link
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let linkString = userInfo["deeplink"] as? String, let url = URL(string: linkString) {
            NotificationCenter.default.post(name: .incomingURL, object: url)
        }
        completionHandler()
    }
}



import SwiftUI
import UserNotifications
import UIKit

@main
struct Kantine_KoningApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear {
                    // Ensure a solid white background across scenes to avoid black areas
                    UIWindow.appearance().backgroundColor = UIColor.white
                    UNUserNotificationCenter.current().delegate = appDelegate
                    appDelegate.store = store
                    store.configurePushNotifications()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Logger.view("App entering foreground - reconciling and refreshing data")
                    store.onAppBecameActive()
                    store.refreshTenantInfo()
                }
        }
    }
}



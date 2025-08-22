import SwiftUI
import UserNotifications

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
        }
    }
}



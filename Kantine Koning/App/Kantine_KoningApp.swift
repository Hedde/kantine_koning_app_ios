import SwiftUI
import UserNotifications
import UIKit

@main
struct Kantine_KoningApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)
                
                // Full-screen maintenance overlay when backend is unavailable
                // Only show when online (offline has its own banner) and backend returns 5xx errors
                if !store.isBackendAvailable && store.isOnline {
                    ServerMaintenanceOverlay(onRetry: {
                        store.retryBackendConnection()
                    })
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.isBackendAvailable)
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



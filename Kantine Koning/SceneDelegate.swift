//
//  SceneDelegate.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 20/01/2025.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
        
        // Handle universal links that opened the app
        for userActivity in connectionOptions.userActivities {
            if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
               let url = userActivity.webpageURL {
                NotificationCenter.default.post(name: .incomingURL, object: url)
            }
        }
        
        // Handle custom URL schemes that opened the app
        for urlContext in connectionOptions.urlContexts {
            NotificationCenter.default.post(name: .incomingURL, object: urlContext.url)
        }
    }

    // Handle universal links into our app when app is already running
    // This allows your app to open links to your domain, rather than opening in a browser tab.
    // See https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        // Ensure we're trying to launch a link.
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let incomingURL = userActivity.webpageURL else {
            return
        }

        // Handle it in our app
        NotificationCenter.default.post(name: .incomingURL, object: incomingURL)
    }
    
    // Handle custom URL schemes when app is already running
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            NotificationCenter.default.post(name: .incomingURL, object: context.url)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
    }
}

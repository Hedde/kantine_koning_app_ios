//
//  Kantine_KoningApp.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI

@main
struct Kantine_KoningApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@StateObject private var model = AppModel()

	var body: some Scene {
		WindowGroup {
			AppRouterView()
				.environmentObject(model)
				.onReceive(NotificationCenter.default.publisher(for: .pushTokenUpdated)) { notification in
					if let token = notification.object as? String {
						model.setPushToken(token)
					}
				}
				.onReceive(NotificationCenter.default.publisher(for: .incomingURL)) { notification in
					if let url = notification.object as? URL {
						model.handleIncomingURL(url)
					}
				}
		}
	}
}

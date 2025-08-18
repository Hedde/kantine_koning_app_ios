//
//  NotificationPermissionCardView.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 18/08/2025.
//

import SwiftUI
import UserNotifications

struct NotificationPermissionCardView: View {
	@State private var permissionStatus: UNAuthorizationStatus = .notDetermined
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Meldingen vereist")
				.font(KKFont.body(12))
				.foregroundStyle(KKTheme.textSecondary)
			
			HStack {
				Image(systemName: statusIcon)
					.foregroundStyle(statusColor)
					.font(.title2)
				VStack(alignment: .leading, spacing: 4) {
					Text(titleText)
						.font(KKFont.title(16))
						.fontWeight(.semibold)
						.foregroundStyle(KKTheme.textPrimary)
					Text(subtitleText)
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
				}
				Spacer()
			}
			
			VStack(alignment: .leading, spacing: 8) {
				Text("💡 Waarom zijn meldingen essentieel?")
					.font(KKFont.body(14))
					.fontWeight(.medium)
					.foregroundStyle(KKTheme.textPrimary)
				Text("• Je krijgt direct bericht wanneer je staat ingepland\n• Geen meldingen = je mist belangrijke diensten\n• Managers kunnen je niet bereiken voor wijzigingen")
					.font(KKFont.body(13))
					.foregroundStyle(KKTheme.textSecondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			
			Button(action: handleButtonTap) {
				HStack {
					Image(systemName: buttonIcon)
					Text(buttonText)
				}
			}
			.buttonStyle(KKPrimaryButton())
			.disabled(permissionStatus == .authorized)
		}
		.kkCard()
		.onAppear {
			checkPermissionStatus()
		}
		.onReceive(NotificationCenter.default.publisher(for: .pushPermissionGranted)) { _ in
			permissionStatus = .authorized
		}
		.onReceive(NotificationCenter.default.publisher(for: .pushPermissionDenied)) { _ in
			permissionStatus = .denied
		}
		.onReceive(NotificationCenter.default.publisher(for: .pushPermissionStatusChecked)) { notification in
			if let status = notification.object as? UNAuthorizationStatus {
				permissionStatus = status
			}
		}
	}
	
	private var statusIcon: String {
		switch permissionStatus {
		case .authorized: return "checkmark.circle.fill"
		case .denied: return "xmark.circle.fill"
		default: return "exclamationmark.triangle.fill"
		}
	}
	
	private var statusColor: Color {
		switch permissionStatus {
		case .authorized: return .green
		case .denied: return .red
		default: return .orange
		}
	}
	
	private var titleText: String {
		switch permissionStatus {
		case .authorized: return "Meldingen ingeschakeld ✓"
		case .denied: return "Meldingen uitgeschakeld"
		default: return "Deze app heeft alleen nut als je meldingen toestaat"
		}
	}
	
	private var subtitleText: String {
		switch permissionStatus {
		case .authorized: return "Perfect! Je ontvangt alle belangrijke meldingen"
		case .denied: return "Schakel meldingen in via iPhone Instellingen"
		default: return "Zonder meldingen mis je belangrijke diensten"
		}
	}
	
	private var buttonText: String {
		switch permissionStatus {
		case .authorized: return "Meldingen staan aan"
		case .denied: return "Open iPhone Instellingen"
		default: return "Sta meldingen toe (verplicht)"
		}
	}
	
	private var buttonIcon: String {
		switch permissionStatus {
		case .authorized: return "checkmark.circle.fill"
		case .denied: return "gear"
		default: return "bell.badge.fill"
		}
	}
	
	private func handleButtonTap() {
		switch permissionStatus {
		case .notDetermined:
			// First time - show Apple system prompt
			(UIApplication.shared.delegate as? AppDelegate)?.requestPushAuthorization()
		case .denied:
			// Already denied - open Settings
			if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
				UIApplication.shared.open(settingsUrl)
			}
		case .authorized:
			// Already granted - maybe check status again
			checkPermissionStatus()
		default:
			break
		}
	}
	
	private func checkPermissionStatus() {
		(UIApplication.shared.delegate as? AppDelegate)?.checkNotificationPermissionStatus()
	}
}

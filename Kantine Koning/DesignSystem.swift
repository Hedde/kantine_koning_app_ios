//
//  DesignSystem.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import SwiftUI
import UIKit

enum KKTheme {
	// Brand palette: white + orange; no black surfaces
	static let accent = Color(hex: 0xF68B2C) // Oranje
	static let textPrimary = Color(hex: 0x27303A) // Donkergrijs/blauw i.p.v. zwart
	static let textSecondary = Color(hex: 0x6B7280)
	static let surface = Color.white
	static let surfaceAlt = Color(hex: 0xFAFAFB)
}

// MARK: - Fonts

enum KKFont {
	private static func available(_ name: String, size: CGFloat) -> Bool {
		UIFont(name: name, size: size) != nil
	}

	static func heading(_ size: CGFloat) -> Font {
		if available("Comfortaa-Bold", size: size) {
			return .custom("Comfortaa-Bold", size: size)
		}
		return .system(size: size, weight: .bold, design: .rounded)
	}

	static func title(_ size: CGFloat) -> Font {
		if available("Comfortaa-SemiBold", size: size) || available("Comfortaa-Medium", size: size) {
			return .custom(available("Comfortaa-SemiBold", size: size) ? "Comfortaa-SemiBold" : "Comfortaa-Medium", size: size)
		}
		return .system(size: size, weight: .semibold, design: .rounded)
	}

	static func body(_ size: CGFloat) -> Font {
		if available("Comfortaa-Regular", size: size) {
			return .custom("Comfortaa-Regular", size: size)
		}
		return .system(size: size, weight: .regular, design: .rounded)
	}
}

extension Color {
	init(hex: UInt, alpha: Double = 1) {
		self.init(
			.sRGB,
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255,
			opacity: alpha
		)
	}
}

struct KKPrimaryButton: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.headline)
			.foregroundColor(.white)
			.padding(.vertical, 14)
			.frame(maxWidth: .infinity)
			.background(KKTheme.accent.opacity(configuration.isPressed ? 0.85 : 1))
			.clipShape(Capsule())
			.contentShape(Rectangle())
	}
}

struct KKSecondaryButton: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.headline)
			.foregroundColor(KKTheme.accent)
			.padding(.vertical, 14)
			.frame(maxWidth: .infinity)
			.background(
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.strokeBorder(KKTheme.accent.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1)
			)
			.contentShape(Rectangle())
	}
}

struct KKCard: ViewModifier {
	func body(content: Content) -> some View {
		content
			.padding(16)
			.background(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(KKTheme.surface)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.stroke(KKTheme.textSecondary.opacity(0.15), lineWidth: 1)
			)
	}
}

extension View {
	func kkCard() -> some View { modifier(KKCard()) }
}

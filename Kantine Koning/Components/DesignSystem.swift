import SwiftUI
import UIKit

enum KKTheme {
    static let accent = Color(hex: 0xF68B2C)
    static let textPrimary = Color(hex: 0x27303A)
    static let textSecondary = Color(hex: 0x6B7280)
    static let surface = Color.white
    static let surfaceAlt = Color(hex: 0xFAFAFB)
}

enum KKFont {
    private static func available(_ name: String, size: CGFloat) -> Bool { UIFont(name: name, size: size) != nil }
    static func heading(_ size: CGFloat) -> Font {
        if available("Comfortaa-Bold", size: size) { return .custom("Comfortaa-Bold", size: size) }
        return .system(size: size, weight: .bold, design: .rounded)
    }
    static func title(_ size: CGFloat) -> Font {
        if available("Comfortaa-SemiBold", size: size) || available("Comfortaa-Medium", size: size) {
            return .custom(available("Comfortaa-SemiBold", size: size) ? "Comfortaa-SemiBold" : "Comfortaa-Medium", size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat) -> Font {
        if available("Comfortaa-Regular", size: size) { return .custom("Comfortaa-Regular", size: size) }
        return .system(size: size, weight: .regular, design: .rounded)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct KKPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(KKTheme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            )
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

extension View { func kkCard() -> some View { modifier(KKCard()) } }

// MARK: - Input styling (old app style)
struct KKTextFieldStyle: TextFieldStyle {
    let placeholder: String?
    init(placeholder: String? = nil) { self.placeholder = placeholder }
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // Darker background for better placeholder contrast
            .background(Color(hex: 0xF0F0F2))
            .cornerRadius(8)
            .font(KKFont.body(16))
            .foregroundColor(KKTheme.textPrimary)
            .tint(KKTheme.accent)
    }
}

extension View {
    func kkTextField() -> some View { textFieldStyle(KKTextFieldStyle()) }
}

// MARK: - Selectable row used for role and team selection (old app style)
struct KKSelectableRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var isDisabled: Bool = false
    var disabledReason: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KKFont.title(16))
                        .foregroundStyle(isDisabled ? KKTheme.textSecondary.opacity(0.6) : KKTheme.textPrimary)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    if isDisabled, let reason = disabledReason {
                        Text(reason)
                            .font(KKFont.body(11))
                            .foregroundStyle(KKTheme.textSecondary.opacity(0.8))
                            .italic()
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDisabled ? KKTheme.textSecondary.opacity(0.4) : (isSelected ? KKTheme.accent : KKTheme.textSecondary))
            }
            .padding(16)
            .background(isDisabled ? KKTheme.surfaceAlt.opacity(0.6) : (isSelected ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDisabled ? Color.clear : (isSelected ? KKTheme.accent.opacity(0.6) : Color.clear), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
}



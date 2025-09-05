import SwiftUI
import UIKit

struct EnrollmentPendingHostView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)
                BrandAssets.logoImage()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                VStack(spacing: 8) {
                    Text("CHECK JE EMAIL")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Bijna klaar!")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)

                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(KKTheme.accent)
                    .padding(.vertical, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructies")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    Text("We hebben een bevestigingslink naar je e-mailadres gestuurd. Open de link op dit toestel om je aanmelding te voltooien.")
                        .font(KKFont.body(14))
                        .foregroundStyle(KKTheme.textSecondary)
                    
                    // Development paste button for magic links
                    #if DEBUG
                    developmentPasteButton()
                    #elseif ENABLE_LOGGING
                    developmentPasteButton()
                    #endif
                }
                .kkCard()
                .padding(.horizontal, 24)

                Spacer(minLength: 60)
            }
        }
        .background(KKTheme.surface.ignoresSafeArea())
    }
    
    @ViewBuilder
    private func developmentPasteButton() -> some View {
        VStack(spacing: 8) {
            Text("Development/Testing")
                .font(KKFont.body(10))
                .foregroundStyle(KKTheme.textSecondary)
                .italic()
            
            Button(action: pasteEnrollmentLink) {
                HStack(spacing: 6) {
                    Image(systemName: "clipboard")
                    Text("Paste Magic Link")
                }
                .font(KKFont.body(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(6)
            }
        }
        .padding(.top, 8)
    }
    
    private func pasteEnrollmentLink() {
        guard let clipboardString = UIPasteboard.general.string else {
            Logger.debug("📋 No text found in clipboard for magic link")
            return
        }
        
        Logger.debug("📋 Attempting to paste magic link: \(clipboardString.prefix(80))...")
        
        // Try to create URL from clipboard content
        guard let url = URL(string: clipboardString) else {
            Logger.debug("❌ Invalid URL format in clipboard")
            return
        }
        
        // Verify it's an enrollment link
        guard DeepLink.isEnrollment(url) else {
            Logger.debug("❌ Clipboard URL is not a valid enrollment link")
            return
        }
        
        Logger.success("✅ Processing pasted magic link")
        store.handleIncomingURL(url)
    }
}



import SwiftUI

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
                }
                .kkCard()
                .padding(.horizontal, 24)

                Spacer(minLength: 60)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .background(KKTheme.surface.ignoresSafeArea())
    }
}



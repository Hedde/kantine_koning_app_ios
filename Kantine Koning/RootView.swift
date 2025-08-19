import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            switch store.appPhase {
            case .launching:
                SplashView()
            case .onboarding:
                OnboardingHostView()
            case .registered:
                HomeHostView()
            case .enrollmentPending(_):
                EnrollmentPendingHostView()
            }
        }
        .onOpenURL { url in store.handleIncomingURL(url) }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            KKTheme.surface.ignoresSafeArea()
            VStack(spacing: 20) {
                BrandAssets.logoImage()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                Text("Kantine Koning")
                    .font(KKFont.heading(34))
                    .foregroundStyle(KKTheme.textPrimary)
                ProgressView()
            }
            .padding()
        }
    }
}



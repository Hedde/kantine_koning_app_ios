import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Namespace private var animation

    var body: some View {
        Group {
            switch store.appPhase {
            case .launching:
                SplashView(namespace: animation)
            case .onboarding:
                OnboardingHostView(namespace: animation)
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
    let namespace: Namespace.ID
    
    var body: some View {
        ZStack {
            // Background afbeelding (volledig scherm)
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            // Donkere overlay voor leesbaarheid
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                BrandAssets.logoImage()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                Text("Kantine Koning")
                    .font(KKFont.heading(34))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
            }
            .padding()
        }
    }
}



//
//  AppRouterView.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI

struct AppRouterView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.appPhase {
            case .launching:
                SplashView()
            case .onboarding:
                OnboardingFlowView()
                    .environmentObject(model)
            case .enrollmentPending:
                EnrollmentPendingView()
                    .environmentObject(model)
            case .registered:
                HomeView()
                    .environmentObject(model)
            }
        }
        .onAppear {
            // Validate manager status when app opens
            if model.appPhase == .registered {
                model.validateManagerStatus()
            }
        }
        .onOpenURL { url in
            model.handleIncomingURL(url)
        }
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



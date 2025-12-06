import SwiftUI

/// A reusable banner view that shows global system-level banners
/// Matches the exact pattern of TenantBannerView for consistency
struct GlobalBannerView: View {
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        VStack(spacing: 0) {
            if !store.globalBanners.isEmpty {
                BannerCarousel(banners: store.globalBanners)
                    .padding(.horizontal, 16)
                    .onAppear {
                        Logger.debug("🌍 Showing \(store.globalBanners.count) global banners")
                    }
            } else {
                // Always show a minimal container to ensure onAppear triggers
                Color.clear
                    .frame(height: 1) // Minimal height to ensure the view exists
                    .onAppear {
                        Logger.debug("🔄 Global banners not loaded yet")
                    }
            }
        }
    }
}


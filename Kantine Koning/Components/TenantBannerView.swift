import SwiftUI

/// A reusable banner view that shows banners for a specific tenant
/// Safely fails if banners cannot be loaded - won't break core functionality
struct TenantBannerView: View {
    let tenantSlug: String
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        if let banners = store.banners[tenantSlug], !banners.isEmpty {
            BannerCarousel(banners: banners)
                .padding(.horizontal, 16)
                .onAppear {
                    Logger.debug("Showing \(banners.count) banners for tenant \(tenantSlug)")
                }
        } else {
            // No banners available - show nothing (fail silently)
            EmptyView()
        }
    }
}

#if DEBUG
struct TenantBannerView_Previews: PreviewProvider {
    static var previews: some View {
        let store = AppStore()
        
        // Mock some banner data
        store.banners["demo"] = [
            DomainModel.Banner(
                id: "1",
                tenantSlug: "demo",
                name: "Sponsor ABC",
                fileUrl: "https://via.placeholder.com/600x100/FF6B35/FFFFFF?text=Sponsor+ABC",
                linkUrl: "https://example.com",
                altText: "Sponsor ABC logo",
                displayOrder: 1
            ),
            DomainModel.Banner(
                id: "2",
                tenantSlug: "demo",
                name: "Sponsor XYZ",
                fileUrl: "https://via.placeholder.com/600x100/4ECDC4/FFFFFF?text=Sponsor+XYZ",
                linkUrl: nil,
                altText: "Sponsor XYZ logo",
                displayOrder: 2
            )
        ]
        
        return VStack(spacing: 20) {
            TenantBannerView(tenantSlug: "demo")
                .environmentObject(store)
            
            Text("Andere content hier...")
                .padding()
            
            Spacer()
        }
        .background(KKTheme.surface)
    }
}
#endif

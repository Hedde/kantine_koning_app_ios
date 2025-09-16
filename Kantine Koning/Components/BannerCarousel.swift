import SwiftUI
import UIKit

struct BannerCarousel: View {
    let banners: [DomainModel.Banner]
    @State private var currentIndex = 0
    @State private var timer: Timer?
    
    private let carouselHeight: CGFloat = 80
    private let aspectRatio: CGFloat = 6.0 // 6:1 ratio as recommended in docs
    
    var body: some View {
        Group {
            if banners.isEmpty {
                EmptyView()
            } else if banners.count == 1 {
                // Single banner - no carousel needed
                SingleBannerView(banner: banners[0])
                    .frame(height: carouselHeight)
            } else {
                // Multiple banners - carousel with auto-rotation
                TabView(selection: $currentIndex) {
                    ForEach(Array(banners.enumerated()), id: \.element.id) { index, banner in
                        SingleBannerView(banner: banner)
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: carouselHeight)
                .clipped()
            }
        }
        .onAppear {
            startAutoRotation()
        }
        .onDisappear {
            stopAutoRotation()
        }
        .onChange(of: banners.count) { _, newCount in
            // Reset carousel when banners change
            if currentIndex >= newCount {
                currentIndex = 0
            }
            restartAutoRotation()
        }
    }
    
    private func startAutoRotation() {
        guard banners.count > 1 else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                currentIndex = (currentIndex + 1) % banners.count
            }
        }
    }
    
    private func stopAutoRotation() {
        timer?.invalidate()
        timer = nil
    }
    
    private func restartAutoRotation() {
        stopAutoRotation()
        startAutoRotation()
    }
}

private struct SingleBannerView: View {
    let banner: DomainModel.Banner
    @State private var showErrorPlaceholder = false
    
    var body: some View {
        Button(action: {
            handleBannerTap()
        }) {
            ZStack {
                if showErrorPlaceholder {
                    // Error placeholder with sponsor info
                    HStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(KKTheme.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(banner.name)
                                .font(KKFont.title(14))
                                .foregroundStyle(KKTheme.textPrimary)
                                .lineLimit(1)
                            Text("Sponsor")
                                .font(KKFont.body(12))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        if banner.hasLink {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(KKTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(KKTheme.surfaceAlt)
                    .cornerRadius(8)
                } else {
                    // Banner image
                    CachedAsyncImage(url: banner.imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(6.0, contentMode: .fit) // 6:1 aspect ratio
                            .clipped()
                    } placeholder: {
                        // Loading placeholder
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(banner.name)
                                    .font(KKFont.title(14))
                                    .foregroundStyle(KKTheme.textPrimary)
                                    .lineLimit(1)
                                Text("Laden...")
                                    .font(KKFont.body(12))
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(KKTheme.surfaceAlt)
                        .cornerRadius(8)
                    }
                    .accessibilityLabel(banner.altText ?? banner.name)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func handleBannerTap() {
        guard banner.hasLink, let linkUrlString = banner.linkUrl, let url = URL(string: linkUrlString) else {
            // Banner has no link - do nothing silently
            return
        }
        
        Logger.userInteraction("Tap", target: "Banner", context: [
            "banner_id": banner.id,
            "banner_name": banner.name,
            "tenant": banner.tenantSlug,
            "link_url": linkUrlString
        ])
        
        // Open in default browser - Apple compliant approach
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    Logger.success("Banner link opened successfully: \(linkUrlString)")
                } else {
                    Logger.error("Failed to open banner link: \(linkUrlString)")
                }
            }
        } else {
            Logger.error("Cannot open banner URL: \(linkUrlString)")
        }
    }
}

#if DEBUG
struct BannerCarousel_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Single banner
            BannerCarousel(banners: [
                DomainModel.Banner(
                    id: "1",
                    tenantSlug: "demo",
                    name: "Sponsor ABC",
                    fileUrl: "https://via.placeholder.com/600x100/FF6B35/FFFFFF?text=Sponsor+ABC",
                    linkUrl: "https://example.com",
                    altText: "Sponsor ABC logo",
                    displayOrder: 1
                )
            ])
            
            // Multiple banners
            BannerCarousel(banners: [
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
                    linkUrl: "https://example2.com",
                    altText: "Sponsor XYZ logo",
                    displayOrder: 2
                )
            ])
            
            Spacer()
        }
        .padding()
        .background(KKTheme.surface)
    }
}
#endif

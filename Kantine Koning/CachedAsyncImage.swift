import SwiftUI

/// Drop-in replacement for AsyncImage that provides intelligent caching
/// Shows cached images immediately while loading fresh ones in background
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: url) { _, newURL in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else {
            image = nil
            return
        }
        
        // Check cache first
        if let cachedImage = CacheManager.shared.getCachedImage(forURL: url) {
            Logger.debug("Using cached image for: \(url)")
            image = cachedImage
            // Still load fresh image in background if cache is stale
            loadFreshImageInBackground()
        } else {
            // No cached image, load from network
            loadFreshImage()
        }
    }
    
    private func loadFreshImage() {
        guard let url = url, !isLoading else { return }
        
        isLoading = true
        Logger.network("Loading image from: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    Logger.success("Image loaded successfully")
                    image = loadedImage
                    CacheManager.shared.cacheImage(loadedImage, forURL: url)
                } else if let error = error {
                    Logger.error("Failed to load image: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func loadFreshImageInBackground() {
        guard let url = url else { return }
        
        // Load fresh image in background without affecting UI
        DispatchQueue.global(qos: .background).async {
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let data = data, let loadedImage = UIImage(data: data) {
                    Logger.debug("Background image refresh completed")
                    CacheManager.shared.cacheImage(loadedImage, forURL: url)
                    
                    // Update UI if the image is different
                    DispatchQueue.main.async {
                        if image?.pngData() != loadedImage.pngData() {
                            image = loadedImage
                        }
                    }
                }
            }.resume()
        }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(url: url) { image in
            image.resizable()
        } placeholder: {
            Color.gray.opacity(0.3)
        }
    }
}

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content) {
            Color.gray.opacity(0.3)
        }
    }
}
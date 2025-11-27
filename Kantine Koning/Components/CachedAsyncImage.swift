import SwiftUI

/// Simple image cache that can be used by any view
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 100 // Limit to 100 images
    }
    
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: NSString(string: url.absoluteString))
    }
    
    func setImage(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: NSString(string: url.absoluteString))
    }
    
    /// Clear all cached images (called during app reset)
    func clearAll() {
        cache.removeAllObjects()
        Logger.debug("🖼️ ImageCache cleared")
    }
}

/// Simple AsyncImage replacement with basic in-memory caching
/// Loads images on demand without complex cache management
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
            // Reset image state and reload when URL changes
            image = nil
            loadImage()
        }
        // Add id to force view refresh when URL changes from nil to value or vice versa
        .id(url?.absoluteString ?? "placeholder")
    }
    
    private func loadImage() {
        guard let url = url else {
            Logger.debug("🖼️ CachedAsyncImage: No URL provided, showing placeholder")
            image = nil
            return
        }
        
        // Check simple in-memory cache first
        if let cachedImage = ImageCache.shared.image(for: url) {
            Logger.debug("🖼️ Using cached image for: \(url.lastPathComponent)")
            image = cachedImage
            return
        }
        
        // Load from network
        Logger.debug("🖼️ Loading fresh image from: \(url.lastPathComponent)")
        loadFreshImage()
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
                    
                    // Cache in memory
                    ImageCache.shared.setImage(loadedImage, for: url)
                } else if let error = error {
                    Logger.error("Failed to load image: \(error.localizedDescription)")
                }
            }
        }.resume()
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
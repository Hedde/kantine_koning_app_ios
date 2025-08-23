import Foundation
import UIKit

/// Comprehensive caching system for offline-first user experience
/// Handles both data caching (JSON responses) and image caching with TTL support
final class CacheManager {
    static let shared = CacheManager()
    
    // MARK: - Configuration
    private struct CacheConfig {
        static let defaultDataTTL: TimeInterval = 300 // 5 minutes for data
        static let longDataTTL: TimeInterval = 3600 // 1 hour for tenant info/logos
        static let imageTTL: TimeInterval = 86400 // 24 hours for images
        static let maxMemoryCacheSize: Int = 50 * 1024 * 1024 // 50MB
        static let maxDiskCacheSize: Int = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Cache Storage
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskCacheURL: URL
    private let imageCache = NSCache<NSString, UIImage>()
    private let cacheQueue = DispatchQueue(label: "com.kantinekoning.cache", qos: .utility)
    
    // MARK: - Cache Entry
    private class CacheEntry {
        let data: Data
        let timestamp: Date
        let ttl: TimeInterval
        
        init(data: Data, ttl: TimeInterval = CacheConfig.defaultDataTTL) {
            self.data = data
            self.timestamp = Date()
            self.ttl = ttl
        }
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
        
        var isStale: Bool {
            // Consider data stale after 50% of TTL for background refresh
            Date().timeIntervalSince(timestamp) > (ttl * 0.5)
        }
    }
    
    // MARK: - Initialization
    private init() {
        // Setup disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("KantineKoningCache")
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Configure memory caches
        memoryCache.totalCostLimit = CacheConfig.maxMemoryCacheSize
        imageCache.totalCostLimit = CacheConfig.maxMemoryCacheSize / 2
        
        Logger.debug("CacheManager initialized with disk cache at: \(diskCacheURL.path)")
    }
    
    // MARK: - Data Caching
    
    /// Cache data with specified TTL
    func cache<T: Codable>(_ object: T, forKey key: String, ttl: TimeInterval = CacheConfig.defaultDataTTL) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(object)
                let entry = CacheEntry(data: data, ttl: ttl)
                
                // Store in memory
                self.memoryCache.setObject(entry, forKey: NSString(string: key))
                
                // Store on disk
                let fileURL = self.diskCacheURL.appendingPathComponent(key.sha256)
                try data.write(to: fileURL)
                
                Logger.debug("Cached data for key: \(key)")
            } catch {
                Logger.error("Failed to cache data for key \(key): \(error)")
            }
        }
    }
    
    /// Retrieve cached data
    func getCached<T: Codable>(_ type: T.Type, forKey key: String) -> CachedResult<T> {
        // Check memory cache first
        if let entry = memoryCache.object(forKey: NSString(string: key)) {
            if !entry.isExpired {
                do {
                    let object = try JSONDecoder().decode(type, from: entry.data)
                    Logger.debug("Cache hit (memory) for key: \(key)")
                    return .fresh(object)
                } catch {
                    Logger.warning("Failed to decode cached data from memory: \(error)")
                }
            } else {
                // Remove expired entry
                memoryCache.removeObject(forKey: NSString(string: key))
            }
        }
        
        // Check disk cache
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256)
        if let data = try? Data(contentsOf: fileURL),
           let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            
            let age = Date().timeIntervalSince(modificationDate)
            let ttl = CacheConfig.defaultDataTTL // Could be stored in metadata
            
            if age <= ttl {
                do {
                    let object = try JSONDecoder().decode(type, from: data)
                    
                    // Restore to memory cache
                    let entry = CacheEntry(data: data, ttl: ttl)
                    memoryCache.setObject(entry, forKey: NSString(string: key))
                    
                    Logger.debug("Cache hit (disk) for key: \(key)")
                    return age > (ttl * 0.5) ? .stale(object) : .fresh(object)
                } catch {
                    Logger.warning("Failed to decode cached data from disk: \(error)")
                }
            } else {
                // Remove expired file
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        Logger.debug("Cache miss for key: \(key)")
        return .miss
    }
    
    // MARK: - Image Caching
    
    /// Cache image with URL as key
    func cacheImage(_ image: UIImage, forURL url: URL) {
        let key = url.absoluteString
        imageCache.setObject(image, forKey: NSString(string: key))
        
        cacheQueue.async { [weak self] in
            guard let self = self,
                  let data = image.pngData() else { return }
            
            let fileURL = self.diskCacheURL.appendingPathComponent("images").appendingPathComponent(key.sha256)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL)
            
            Logger.debug("Cached image for URL: \(url)")
        }
    }
    
    /// Get cached image
    func getCachedImage(forURL url: URL) -> UIImage? {
        let key = url.absoluteString
        
        // Check memory cache
        if let image = imageCache.object(forKey: NSString(string: key)) {
            Logger.debug("Image cache hit (memory) for URL: \(url)")
            return image
        }
        
        // Check disk cache
        let fileURL = diskCacheURL.appendingPathComponent("images").appendingPathComponent(key.sha256)
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            
            // Check if image is still fresh (24 hours)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) <= CacheConfig.imageTTL {
                
                // Restore to memory cache
                imageCache.setObject(image, forKey: NSString(string: key))
                Logger.debug("Image cache hit (disk) for URL: \(url)")
                return image
            } else {
                // Remove expired image
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        return nil
    }
    
    // MARK: - Cache Management
    
    /// Invalidate specific cache entry
    func invalidateCache(forKey key: String) {
        // Remove from memory cache
        memoryCache.removeObject(forKey: NSString(string: key))
        
        // Remove from disk cache
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.diskCacheURL.appendingPathComponent(key.sha256)
            try? FileManager.default.removeItem(at: fileURL)
            Logger.debug("Cache invalidated for key: \(key)")
        }
    }
    
    /// Clear all cached data
    func clearCache() {
        memoryCache.removeAllObjects()
        imageCache.removeAllObjects()
        
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.diskCacheURL)
            try? FileManager.default.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)
            Logger.info("Cache cleared")
        }
    }
    
    /// Clear expired entries
    func cleanupExpiredEntries() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(at: self.diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            
            var removedCount = 0
            for fileURL in contents {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    
                    let age = Date().timeIntervalSince(modificationDate)
                    let ttl = fileURL.pathExtension == "png" ? CacheConfig.imageTTL : CacheConfig.defaultDataTTL
                    
                    if age > ttl {
                        try? fileManager.removeItem(at: fileURL)
                        removedCount += 1
                    }
                }
            }
            
            if removedCount > 0 {
                Logger.debug("Cleaned up \(removedCount) expired cache entries")
            }
        }
    }
    
    // MARK: - Cache Keys
    
    enum CacheKey {
        static func diensten(tenantSlug: String) -> String {
            return "diensten_\(tenantSlug)"
        }
        
        static func leaderboard(tenantSlug: String, period: String, teamId: String?) -> String {
            return "leaderboard_\(tenantSlug)_\(period)_\(teamId ?? "all")"
        }
        
        static func globalLeaderboard(tenantSlug: String, period: String, teamId: String?) -> String {
            return "global_leaderboard_\(tenantSlug)_\(period)_\(teamId ?? "all")"
        }
        
        static func tenantInfo(tenantSlug: String) -> String {
            return "tenant_info_\(tenantSlug)"
        }
        
        static let allTenantInfo = "all_tenant_info"
    }
}

// MARK: - Cache Result Types

enum CachedResult<T> {
    case fresh(T)    // Data is fresh and valid
    case stale(T)    // Data is valid but should be refreshed in background
    case miss        // No cached data available
    
    var data: T? {
        switch self {
        case .fresh(let data), .stale(let data):
            return data
        case .miss:
            return nil
        }
    }
    
    var shouldRefresh: Bool {
        switch self {
        case .stale, .miss:
            return true
        case .fresh:
            return false
        }
    }
}

// MARK: - String Extension for Cache Keys

private extension String {
    var sha256: String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CommonCrypto Import
import CommonCrypto

import AppKit
import CryptoKit
import Foundation

/// Thread-safe image cache with memory and disk caching.
actor ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let fileManager = FileManager.default
    private let diskCacheURL: URL

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB

        // Set up disk cache directory
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("com.kaset.imagecache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// Fetches an image from cache or network.
    func image(for url: URL) async -> NSImage? {
        // Check memory cache
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(url: url) {
            memoryCache.setObject(diskImage, forKey: url as NSURL)
            return diskImage
        }

        // Check if already fetching
        if let existing = inFlight[url] {
            return await existing.value
        }

        // Fetch from network
        let task = Task<NSImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else { return nil }
                memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
                saveToDisk(url: url, data: data)
                return image
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let result = await task.value
        inFlight.removeValue(forKey: url)
        return result
    }

    /// Prefetches images without blocking.
    func prefetch(urls: [URL]) {
        for url in urls {
            Task.detached(priority: .utility) {
                _ = await self.image(for: url)
            }
        }
    }

    /// Clears the memory cache.
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        inFlight.removeAll()
    }

    /// Clears both memory and disk caches.
    func clearAllCaches() {
        clearMemoryCache()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Disk Cache Helpers

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func diskCachePath(for url: URL) -> URL {
        diskCacheURL.appendingPathComponent(cacheKey(for: url))
    }

    private func loadFromDisk(url: URL) -> NSImage? {
        let path = diskCachePath(for: url)
        guard let data = try? Data(contentsOf: path),
              let image = NSImage(data: data)
        else {
            return nil
        }
        return image
    }

    private func saveToDisk(url: URL, data: Data) {
        let path = diskCachePath(for: url)
        try? data.write(to: path, options: .atomic)
    }
}

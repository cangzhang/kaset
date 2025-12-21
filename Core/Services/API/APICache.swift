import CryptoKit
import Foundation

/// Thread-safe cache for API responses with TTL and LRU eviction support.
/// Uses @MainActor since YTMusicClient is also @MainActor.
@MainActor
final class APICache {
    static let shared = APICache()

    struct CacheEntry {
        let data: [String: Any]
        let timestamp: Date
        let ttl: TimeInterval
        var lastAccessed: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }

        init(data: [String: Any], timestamp: Date, ttl: TimeInterval) {
            self.data = data
            self.timestamp = timestamp
            self.ttl = ttl
            lastAccessed = timestamp
        }
    }

    /// TTL values for different endpoint types.
    enum TTL {
        static let home: TimeInterval = 5 * 60 // 5 minutes
        static let playlist: TimeInterval = 30 * 60 // 30 minutes
        static let artist: TimeInterval = 60 * 60 // 1 hour
        static let search: TimeInterval = 2 * 60 // 2 minutes
    }

    /// Maximum number of cached entries before LRU eviction kicks in.
    private static let maxEntries = 50

    private var cache: [String: CacheEntry] = [:]

    private init() {}

    /// Gets cached data if available and not expired.
    func get(key: String) -> [String: Any]? {
        guard var entry = cache[key] else { return nil }

        if entry.isExpired {
            cache.removeValue(forKey: key)
            return nil
        }

        // Update last accessed time for LRU tracking
        entry.lastAccessed = Date()
        cache[key] = entry
        return entry.data
    }

    /// Stores data in the cache with the specified TTL.
    /// Evicts least recently used entries if cache is at capacity.
    func set(key: String, data: [String: Any], ttl: TimeInterval) {
        // Evict expired entries first
        evictExpiredEntries()

        // Evict LRU entries if still at capacity
        while cache.count >= Self.maxEntries {
            evictLeastRecentlyUsed()
        }

        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
    }

    /// Generates a stable, deterministic cache key from endpoint and request body.
    /// Uses SHA256 hash of sorted JSON to ensure consistency.
    static func stableCacheKey(endpoint: String, body: [String: Any]) -> String {
        let sortedJSON = sortedJSONString(body)
        let hash = SHA256.hash(data: Data(sortedJSON.utf8))
        let hashString = hash.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
        return "\(endpoint):\(hashString)"
    }

    /// Invalidates all cached entries.
    func invalidateAll() {
        cache.removeAll()
    }

    /// Invalidates entries matching the given prefix.
    func invalidate(matching prefix: String) {
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Returns current cache statistics for debugging.
    var stats: (count: Int, expired: Int) {
        let expired = cache.values.filter(\.isExpired).count
        return (cache.count, expired)
    }

    // MARK: - Private Helpers

    /// Evicts all expired entries from the cache.
    private func evictExpiredEntries() {
        cache = cache.filter { !$0.value.isExpired }
    }

    /// Evicts the least recently used entry from the cache.
    private func evictLeastRecentlyUsed() {
        guard let lruKey = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else {
            return
        }
        cache.removeValue(forKey: lruKey)
    }

    /// Creates a sorted, deterministic JSON string from a dictionary.
    private static func sortedJSONString(_ dict: [String: Any]) -> String {
        do {
            // Sort keys and serialize
            let sortedDict = dict.sorted { $0.key < $1.key }
            var result = "{"
            for (index, (key, value)) in sortedDict.enumerated() {
                if index > 0 { result += "," }
                result += "\"\(key)\":\(stringValue(value))"
            }
            result += "}"
            return result
        }
    }

    /// Converts a value to a deterministic string representation.
    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let dict as [String: Any]:
            return sortedJSONString(dict)
        case let array as [Any]:
            let items = array.map { stringValue($0) }.joined(separator: ",")
            return "[\(items)]"
        default:
            return "\"\(value)\""
        }
    }
}

//
//  PlaylistCacheManager.swift
//  tiptv
//

import Foundation

/// Provides ultra-fast local disk caching of parsed channels and VOD catalogs.
/// Enables sub-100ms instant app launch without waiting for network re-downloads.
actor PlaylistCacheManager {
    static let shared = PlaylistCacheManager()

    private let cacheDirectory: URL
    private let cacheFormatVersion = 2
    private let maximumCacheAge: TimeInterval

    private struct CacheEnvelope: Codable {
        let formatVersion: Int
        let createdAt: Date
        let channels: [Channel]
    }

    init(
        cacheDirectory: URL? = nil,
        maximumCacheAge: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.maximumCacheAge = maximumCacheAge
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            self.cacheDirectory = cacheDirectory
            return
        }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = caches.appendingPathComponent("tiptv_playlist_cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheDirectory = dir
        } else {
            self.cacheDirectory = FileManager.default.temporaryDirectory
        }
    }

    private func cacheKey(for urlString: String) -> String {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = clean.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        return String(hash, radix: 16)
    }

    private func channelsURL(for urlString: String) -> URL {
        cacheDirectory.appendingPathComponent("channels_\(cacheKey(for: urlString)).bin")
    }

    private func moviesURL(for urlString: String) -> URL {
        cacheDirectory.appendingPathComponent("movies_\(cacheKey(for: urlString)).bin")
    }

    private func seriesURL(for urlString: String) -> URL {
        cacheDirectory.appendingPathComponent("series_\(cacheKey(for: urlString)).bin")
    }

    // MARK: - Save

    func saveChannels(_ channels: [Channel], for urlString: String) {
        guard !channels.isEmpty, !urlString.isEmpty else { return }
        let fileURL = channelsURL(for: urlString)
        do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
            let data = try encoder.encode(makeEnvelope(channels))
                try data.write(to: fileURL, options: .atomic)
        } catch {
                #if DEBUG
                print("[PlaylistCacheManager] Failed to cache channels: \(error)")
                #endif
        }
    }

    func saveMovies(_ movies: [Channel], for urlString: String) {
        guard !movies.isEmpty, !urlString.isEmpty else { return }
        let fileURL = moviesURL(for: urlString)
        do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
            let data = try encoder.encode(makeEnvelope(movies))
                try data.write(to: fileURL, options: .atomic)
        } catch {
                #if DEBUG
                print("[PlaylistCacheManager] Failed to cache movies: \(error)")
                #endif
        }
    }

    func saveSeries(_ series: [Channel], for urlString: String) {
        guard !series.isEmpty, !urlString.isEmpty else { return }
        let fileURL = seriesURL(for: urlString)
        do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
            let data = try encoder.encode(makeEnvelope(series))
                try data.write(to: fileURL, options: .atomic)
        } catch {
                #if DEBUG
                print("[PlaylistCacheManager] Failed to cache series: \(error)")
                #endif
        }
    }

    // MARK: - Load

    func loadCachedChannels(for urlString: String) async -> [Channel]? {
        guard !urlString.isEmpty else { return nil }
        let fileURL = channelsURL(for: urlString)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return decodeCache(at: fileURL)
    }

    func loadCachedMovies(for urlString: String) async -> [Channel]? {
        guard !urlString.isEmpty else { return nil }
        let fileURL = moviesURL(for: urlString)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return decodeCache(at: fileURL)
    }

    func loadCachedSeries(for urlString: String) async -> [Channel]? {
        guard !urlString.isEmpty else { return nil }
        let fileURL = seriesURL(for: urlString)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return decodeCache(at: fileURL)
    }

    // MARK: - Clear

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clear(for urlString: String) {
        try? FileManager.default.removeItem(at: channelsURL(for: urlString))
        try? FileManager.default.removeItem(at: moviesURL(for: urlString))
        try? FileManager.default.removeItem(at: seriesURL(for: urlString))
    }

    private func makeEnvelope(_ channels: [Channel]) -> CacheEnvelope {
        CacheEnvelope(
            formatVersion: cacheFormatVersion,
            createdAt: Date(),
            channels: channels
        )
    }

    private func decodeCache(at fileURL: URL) -> [Channel]? {
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let envelope = try PropertyListDecoder().decode(CacheEnvelope.self, from: data)
            guard envelope.formatVersion == cacheFormatVersion,
                  Date().timeIntervalSince(envelope.createdAt) <= maximumCacheAge else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return envelope.channels
        } catch {
            // Pre-versioned cache files are discarded and recreated after the next load.
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }
}

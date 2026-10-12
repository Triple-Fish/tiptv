//
//  tiptvCoreTests.swift
//  tiptvCoreTests
//
//  Created by Graham Ward on 11/10/2026.
//

import Foundation
import Testing
@testable import tiptv

struct PlaylistAndCatalogTests {
    @Test func `Parser creates stable identities and preserves metadata`() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="news.uk" tvg-logo="https://example.com/logo.png" group-title="News",UK: NEWS HD
        https://example.com/live/news.m3u8

        # A comment between entries
        #EXTINF:-1 group-title="Movies",Example Film (2025)
        https://example.com/movie/film.mp4
        """

        let first = PlaylistParser.channels(from: playlist)
        let second = PlaylistParser.channels(from: playlist)

        #expect(first.count == 2)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first[0].group == "News")
        #expect(first[0].tvgID == "news.uk")
        #expect(first[0].logoURL == URL(string: "https://example.com/logo.png"))
        #expect(first[1].isMovie)
    }

    @Test @MainActor func `XMLTV programmes match playlist tvg identifiers`() throws {
        let channel = Channel(
            name: "UK News",
            tvgID: "news.uk",
            streamURL: try #require(URL(string: "https://example.com/news.m3u8"))
        )
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="news.uk"><display-name>UK News</display-name></channel>
          <programme start="20261011200000 +0100" stop="20261011210000 +0100" channel="news.uk">
            <title>Evening News</title><desc>Tonight's headlines.</desc><category>News</category>
          </programme>
        </tv>
        """
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xml")
        try Data(xml.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try XMLTVParser.parse(fileURL: fileURL, channels: [channel])
        #expect(result[channel.id]?.first?.title == "Evening News")
    }

    @Test func `Stable identity depends on stream URL`() {
        let first = Channel.stableID(for: "https://example.com/live/1.m3u8")
        let repeated = Channel.stableID(for: "https://example.com/live/1.m3u8")
        let different = Channel.stableID(for: "https://example.com/live/2.m3u8")

        #expect(first == repeated)
        #expect(first != different)
    }

    @Test func `Catalog filtering combines visibility category favorites and search`() throws {
        let news = try makeChannel(name: "World News", url: "https://example.com/news.m3u8", category: .news)
        let sport = try makeChannel(name: "Live Sport", url: "https://example.com/sport.m3u8", category: .sports)
        let channels = [news, sport]

        let visible = ChannelCatalog.visibleChannels(in: channels, hiddenStreamURLs: [sport.streamURLString])
        #expect(visible == [news])

        let favorites = ChannelCatalog.filteredChannels(
            in: channels,
            category: .favorites,
            favoriteStreamURLs: [news.streamURLString],
            query: "world"
        )
        #expect(favorites == [news])
    }

    @Test(arguments: [1_000, 10_000, 50_000])
    func `Large playlists parse completely`(channelCount: Int) {
        var lines = [String]()
        lines.reserveCapacity((channelCount * 2) + 1)
        lines.append("#EXTM3U")
        for index in 0..<channelCount {
            lines.append("#EXTINF:-1 group-title=\"News\",Channel \(index)")
            lines.append("https://example.com/live/\(index).m3u8")
        }

        let channels = PlaylistParser.channels(from: lines.joined(separator: "\n"))
        #expect(channels.count == channelCount)
        #expect(Set(channels.map(\.id)).count == channelCount)
    }

    @Test func `Versioned cache round trips and expires`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let channel = try makeChannel(name: "News", url: "https://example.com/news.m3u8", category: .news)

        let cache = PlaylistCacheManager(cacheDirectory: directory)
        await cache.saveChannels([channel], for: "source")
        let loaded = await cache.loadCachedChannels(for: "source")
        #expect(loaded == [channel])

        let expiredCache = PlaylistCacheManager(cacheDirectory: directory, maximumCacheAge: -1)
        let expired = await expiredCache.loadCachedChannels(for: "source")
        #expect(expired == nil)
    }

    private func makeChannel(name: String, url: String, category: ChannelCategory) throws -> Channel {
        let streamURL = try #require(URL(string: url))
        return Channel(name: name, streamURL: streamURL, category: category)
    }
}

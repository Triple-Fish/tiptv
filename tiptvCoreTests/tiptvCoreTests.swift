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
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).xml")
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
    let news = try makeChannel(
      name: "World News", url: "https://example.com/news.m3u8", category: .news)
    let sport = try makeChannel(
      name: "Live Sport", url: "https://example.com/sport.m3u8", category: .sports)
    let channels = [news, sport]

    let visible = ChannelCatalog.visibleChannels(
      in: channels, hiddenStreamURLs: [sport.streamURLString])
    #expect(visible == [news])

    let favorites = ChannelCatalog.filteredChannels(
      in: channels,
      category: .favorites,
      favoriteStreamURLs: [news.streamURLString],
      query: "world"
    )
    #expect(favorites == [news])
  }

  @Test func `Catalog fast paths preserve filtering results`() throws {
    let news = try makeChannel(
      name: "World News", url: "https://example.com/news.m3u8", category: .news)
    let sport = try makeChannel(
      name: "Live Sport", url: "https://example.com/sport.m3u8", category: .sports)
    let movie = try makeChannel(
      name: "Example Movie", url: "https://example.com/movie.mp4", category: .movies)
    let channels = [news, sport, movie]

    #expect(
      ChannelCatalog.filteredChannels(
        in: channels,
        category: .all,
        favoriteStreamURLs: [],
        query: ""
      ) == channels)
    #expect(
      ChannelCatalog.favoriteChannels(
        in: channels,
        favoriteStreamURLs: [sport.streamURLString]
      ) == [sport])
    #expect(
      ChannelCatalog.videoChannels(
        in: channels,
        group: nil,
        pathExtension: nil,
        query: ""
      ) == channels)
    #expect(
      ChannelCatalog.videoChannels(
        in: channels,
        group: nil,
        pathExtension: "mp4",
        query: ""
      ) == [movie])
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
    let channel = try makeChannel(
      name: "News", url: "https://example.com/news.m3u8", category: .news)

    let cache = PlaylistCacheManager(cacheDirectory: directory)
    await cache.saveChannels([channel], for: "source")
    let loaded = await cache.loadCachedChannels(for: "source")
    #expect(loaded == [channel])

    let expiredCache = PlaylistCacheManager(cacheDirectory: directory, maximumCacheAge: -1)
    let expired = await expiredCache.loadCachedChannels(for: "source")
    #expect(expired == nil)
  }

  @Test @MainActor func `Profile passwords round trip through secure storage`() {
    let credentials = PlaylistCredentials.shared
    let profileID = UUID()
    let originalUsername = credentials.username
    let originalPassword = credentials.password
    defer {
      credentials.deletePassword(for: profileID)
      credentials.username = originalUsername
      credentials.password = originalPassword
      credentials.flushPendingChanges()
    }

    credentials.password = "test-password-\(profileID.uuidString)"
    credentials.savePassword(for: profileID)
    credentials.password = ""
    credentials.loadPassword(for: profileID)

    #expect(credentials.password == "test-password-\(profileID.uuidString)")
  }

  @Test func `Playback recovery escalates without looping`() {
    #expect(
      PlaybackRecoveryPolicy.action(
        forAttempt: 1, isPlaying: true, isVOD: false, backupPlayerAllowed: true
      ) == .recovered)
    #expect(
      PlaybackRecoveryPolicy.action(
        forAttempt: 1, isPlaying: false, isVOD: false, backupPlayerAllowed: true
      ) == .reloadNative)
    #expect(
      PlaybackRecoveryPolicy.action(
        forAttempt: 1, isPlaying: false, isVOD: true, backupPlayerAllowed: true
      ) == .showError)
    #expect(
      PlaybackRecoveryPolicy.action(
        forAttempt: 2, isPlaying: false, isVOD: false, backupPlayerAllowed: true
      ) == .switchToBackup)
    #expect(
      PlaybackRecoveryPolicy.action(
        forAttempt: 2, isPlaying: false, isVOD: false, backupPlayerAllowed: false
      ) == .showError)
  }

  @Test func `Parser handles unencoded spaces in stream URLs`() throws {
    let playlist = """
      #EXTM3U
      #EXTINF:-1 group-title="Movies",The Space Movie (2025)
      https://example.com/movie/The Space Movie.mp4
      """

    let channels = PlaylistParser.channels(from: playlist)
    #expect(channels.count == 1)
    #expect(channels.first?.name == "The Space Movie (2025)")
    #expect(channels.first?.isMovie == true)
  }

  @Test @MainActor func `Continue watching records position and clears on completion`() throws {
    let manager = ContinueWatchingManager.shared
    let channel = try makeChannel(
      name: "Feature Film",
      url: "https://example.com/movie/film.mp4",
      category: .movies
    )

    // Record 500s into 1000s movie (50% progress)
    manager.record(channel: channel, position: 500, duration: 1000, force: true)
    #expect(manager.position(for: channel) == 500)

    // Record 960s into 1000s movie (96% progress - triggers auto-completion removal)
    manager.record(channel: channel, position: 960, duration: 1000, force: true)
    #expect(manager.position(for: channel) == nil)
  }

  @Test @MainActor func `Continue watching ignores finite live streams`() throws {
    let manager = ContinueWatchingManager.shared
    let channel = try makeChannel(
      name: "Live Channel",
      url: "https://example.com/live/channel.m3u8",
      category: .entertainment
    )

    manager.remove(channel)
    manager.record(channel: channel, position: 500, duration: 3_600, force: true)
    #expect(manager.position(for: channel) == nil)
  }

  @Test @MainActor func `Series playback manager manages episode queue progression`() throws {
    let ep1 = try makeChannel(
      name: "S01E01 Pilot",
      url: "https://example.com/series/s01e01.mp4",
      category: .series
    )
    let ep2 = try makeChannel(
      name: "S01E02 Second",
      url: "https://example.com/series/s01e02.mp4",
      category: .series
    )

    let manager = SeriesPlaybackManager.shared
    manager.configureM3UQueue(groupChannels: [ep1, ep2], currentChannel: ep1)

    #expect(manager.isSeriesActive)
    #expect(manager.hasNextEpisode)
    #expect(!manager.hasPreviousEpisode)

    let next = manager.advanceToNextEpisode()
    #expect(next?.id == ep2.id)
    #expect(manager.hasPreviousEpisode)
    #expect(!manager.hasNextEpisode)

    let prev = manager.goToPreviousEpisode()
    #expect(prev?.id == ep1.id)

    manager.clearQueue()
    #expect(!manager.isSeriesActive)
  }

  @Test @MainActor func `Series playback follows M3U episodes and clears for unrelated content`() throws {
    let ep1 = try makeChannel(
      name: "Example Show S01E01 Pilot",
      url: "https://example.com/series/example-s01e01.mp4",
      category: .series
    )
    let ep2 = try makeChannel(
      name: "Example Show S01E02 Second",
      url: "https://example.com/series/example-s01e02.mp4",
      category: .series
    )
    let movie = try makeChannel(
      name: "Feature Film",
      url: "https://example.com/movie/feature.mp4",
      category: .movies
    )

    let manager = SeriesPlaybackManager.shared
    manager.preparePlayback(of: ep1, availableChannels: [ep1, ep2, movie])
    #expect(manager.hasNextEpisode)
    #expect(manager.advanceToNextEpisode()?.id == ep2.id)

    manager.preparePlayback(of: movie, availableChannels: [ep1, ep2, movie])
    #expect(!manager.isSeriesActive)
  }

  @Test @MainActor func `Recent channels manager records and filters channels in order`() throws {
    let manager = RecentChannelsManager.shared
    manager.clearRecent()

    let ch1 = try makeChannel(name: "BBC One", url: "https://example.com/bbc1.m3u8", category: .entertainment)
    let ch2 = try makeChannel(name: "Sky Sports", url: "https://example.com/skysports.m3u8", category: .sports)

    manager.recordChannel(ch1)
    manager.recordChannel(ch2)

    let filtered = manager.filterRecent(from: [ch1, ch2])
    #expect(filtered.count == 2)
    #expect(filtered.first?.id == ch2.id)
    #expect(filtered.last?.id == ch1.id)

    manager.clearRecent()
    #expect(manager.filterRecent(from: [ch1, ch2]).isEmpty)
  }

  private func makeChannel(name: String, url: String, category: ChannelCategory) throws -> Channel {
    let streamURL = try #require(URL(string: url))
    return Channel(name: name, streamURL: streamURL, category: category)
  }
}

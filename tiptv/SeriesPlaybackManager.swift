//
//  SeriesPlaybackManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SeriesPlaybackManager: ObservableObject {
  static let shared = SeriesPlaybackManager()

  // MARK: - Autoplay Setting Key
  private let autoplayKey = "tiptv_autoplay_next_episode"

  // MARK: - Published Properties
  @Published var isAutoplayEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isAutoplayEnabled, forKey: autoplayKey)
    }
  }

  @Published private(set) var activeSeries: Channel?
  @Published private(set) var activeSeriesInfo: XtreamSeriesInfo?
  @Published private(set) var episodesQueue: [XtreamEpisode] = []
  @Published private(set) var currentEpisodeIndex: Int = -1

  // Fallback for M3U series groups
  @Published private(set) var m3uQueue: [Channel] = []
  @Published private(set) var currentM3UIndex: Int = -1

  // Autoplay Countdown State
  @Published var isCountdownActive: Bool = false
  @Published var countdownSecondsRemaining: Int = 5
  private var countdownTask: Task<Void, Never>?

  private init() {
    if UserDefaults.standard.object(forKey: autoplayKey) != nil {
      self.isAutoplayEnabled = UserDefaults.standard.bool(forKey: autoplayKey)
    } else {
      self.isAutoplayEnabled = true
    }
  }

  // MARK: - Computed Properties

  var isSeriesActive: Bool {
    !episodesQueue.isEmpty || !m3uQueue.isEmpty
  }

  var currentEpisode: XtreamEpisode? {
    guard currentEpisodeIndex >= 0 && currentEpisodeIndex < episodesQueue.count else { return nil }
    return episodesQueue[currentEpisodeIndex]
  }

  var hasNextEpisode: Bool {
    if !episodesQueue.isEmpty {
      return currentEpisodeIndex >= 0 && currentEpisodeIndex < episodesQueue.count - 1
    }
    if !m3uQueue.isEmpty {
      return currentM3UIndex >= 0 && currentM3UIndex < m3uQueue.count - 1
    }
    return false
  }

  var nextEpisode: XtreamEpisode? {
    guard !episodesQueue.isEmpty, hasNextEpisode else { return nil }
    return episodesQueue[currentEpisodeIndex + 1]
  }

  var nextM3UChannel: Channel? {
    guard !m3uQueue.isEmpty, hasNextEpisode else { return nil }
    return m3uQueue[currentM3UIndex + 1]
  }

  var nextEpisodeTitle: String {
    if let nextEp = nextEpisode {
      return "S\(nextEp.season)E\(nextEp.episodeNum): \(nextEp.title)"
    }
    if let nextM3U = nextM3UChannel {
      return nextM3U.uniformName
    }
    return "Next Episode"
  }

  var hasPreviousEpisode: Bool {
    if !episodesQueue.isEmpty {
      return currentEpisodeIndex > 0
    }
    if !m3uQueue.isEmpty {
      return currentM3UIndex > 0
    }
    return false
  }

  // MARK: - Queue Setup

  /// Sets up queue for Xtream Codes series with season and episode hierarchy
  func configureQueue(
    series: Channel, seriesInfo: XtreamSeriesInfo?, startingWith episode: XtreamEpisode
  ) {
    cancelCountdown()
    m3uQueue = []
    currentM3UIndex = -1

    self.activeSeries = series
    self.activeSeriesInfo = seriesInfo

    if let info = seriesInfo {
      let sortedSeasons = info.seasons.sorted()
      var ordered: [XtreamEpisode] = []
      for season in sortedSeasons {
        let seasonEps = (info.episodesBySeason[season] ?? []).sorted(by: {
          $0.episodeNum < $1.episodeNum
        })
        ordered.append(contentsOf: seasonEps)
      }
      self.episodesQueue = ordered
    } else {
      self.episodesQueue = [episode]
    }

    self.currentEpisodeIndex = episodesQueue.firstIndex(where: { $0.id == episode.id }) ?? 0
  }

  /// Sets up queue for M3U playlist channels sharing the same series group
  func configureM3UQueue(groupChannels: [Channel], currentChannel: Channel) {
    cancelCountdown()
    episodesQueue = []
    currentEpisodeIndex = -1
    activeSeries = nil
    activeSeriesInfo = nil

    self.m3uQueue = groupChannels
    self.currentM3UIndex = groupChannels.firstIndex(where: { $0.id == currentChannel.id }) ?? 0
  }

  /// Aligns the shared queue with the item being opened and clears stale series state
  /// when playback moves to unrelated content.
  func preparePlayback(of channel: Channel, availableChannels: [Channel]) {
    cancelCountdown()

    if !episodesQueue.isEmpty,
      let index = episodesQueue.firstIndex(where: { $0.streamURL == channel.streamURL })
    {
      currentEpisodeIndex = index
      return
    }

    guard channel.isSeries, let seriesKey = m3uSeriesKey(for: channel) else {
      clearQueue()
      return
    }

    let matchingEpisodes = availableChannels.filter {
      $0.isSeries && m3uSeriesKey(for: $0) == seriesKey
    }
    guard matchingEpisodes.contains(where: { $0.id == channel.id }) else {
      clearQueue()
      return
    }

    configureM3UQueue(groupChannels: matchingEpisodes, currentChannel: channel)
  }

  // MARK: - Navigation

  /// Advances to next episode and returns the Channel to play
  func advanceToNextEpisode() -> Channel? {
    cancelCountdown()

    if !episodesQueue.isEmpty {
      guard hasNextEpisode else { return nil }
      currentEpisodeIndex += 1
      guard let ep = currentEpisode, let series = activeSeries else { return nil }
      return channel(for: ep, series: series, coverURL: activeSeriesInfo?.coverURL)
    }

    if !m3uQueue.isEmpty {
      guard hasNextEpisode else { return nil }
      currentM3UIndex += 1
      return m3uQueue[currentM3UIndex]
    }

    return nil
  }

  /// Rewinds to previous episode and returns the Channel to play
  func goToPreviousEpisode() -> Channel? {
    cancelCountdown()

    if !episodesQueue.isEmpty {
      guard hasPreviousEpisode else { return nil }
      currentEpisodeIndex -= 1
      guard let ep = currentEpisode, let series = activeSeries else { return nil }
      return channel(for: ep, series: series, coverURL: activeSeriesInfo?.coverURL)
    }

    if !m3uQueue.isEmpty {
      guard hasPreviousEpisode else { return nil }
      currentM3UIndex -= 1
      return m3uQueue[currentM3UIndex]
    }

    return nil
  }

  /// Builds a Channel model from an XtreamEpisode
  func channel(for episode: XtreamEpisode, series: Channel, coverURL: URL?) -> Channel {
    Channel(
      name: "\(series.uniformName) S\(episode.season)E\(episode.episodeNum): \(episode.title)",
      uniformName:
        "\(series.uniformName) S\(episode.season)E\(episode.episodeNum): \(episode.title)",
      group: series.uniformName,
      logoURL: coverURL ?? series.logoURL,
      streamURL: episode.streamURL,
      streamURLString: episode.streamURL.absoluteString,
      category: .series
    )
  }

  /// Clears any series context
  func clearQueue() {
    cancelCountdown()
    activeSeries = nil
    activeSeriesInfo = nil
    episodesQueue = []
    currentEpisodeIndex = -1
    m3uQueue = []
    currentM3UIndex = -1
  }

  private func m3uSeriesKey(for channel: Channel) -> String? {
    let name = channel.uniformName.lowercased()
    guard let episodeRange = name.range(
      of: #"\bs\d{1,3}\s*e\d{1,3}\b"#,
      options: .regularExpression
    ) else { return nil }

    let title = name[..<episodeRange.lowerBound]
      .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—:|._")))
    guard !title.isEmpty else { return nil }
    return title
  }

  // MARK: - Autoplay & Countdown

  /// Called when the player reaches the end of an episode
  func handleEpisodePlaybackEnded(onPlayNext: @escaping (Channel) -> Void) {
    guard hasNextEpisode else { return }

    if isAutoplayEnabled {
      startCountdown(onPlayNext: onPlayNext)
    } else {
      // Even if autoplay is disabled, show the prompt so user can tap Play Next
      isCountdownActive = true
      countdownSecondsRemaining = 0
    }
  }

  /// Starts a 5-second countdown to autoplay the next episode
  func startCountdown(onPlayNext: @escaping (Channel) -> Void) {
    cancelCountdown()
    guard hasNextEpisode else { return }

    isCountdownActive = true
    countdownSecondsRemaining = 5

    countdownTask = Task {
      for sec in stride(from: 5, through: 1, by: -1) {
        if Task.isCancelled { return }
        self.countdownSecondsRemaining = sec
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }

      if Task.isCancelled { return }
      self.playNextNow(onPlayNext: onPlayNext)
    }
  }

  /// Plays the next episode immediately
  func playNextNow(onPlayNext: @escaping (Channel) -> Void) {
    cancelCountdown()
    if let nextChannel = advanceToNextEpisode() {
      onPlayNext(nextChannel)
    }
  }

  /// Cancels active countdown
  func cancelCountdown() {
    countdownTask?.cancel()
    countdownTask = nil
    isCountdownActive = false
  }
}

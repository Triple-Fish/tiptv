//
//  ContentView.swift
//  tiptv
//

import AVFoundation
import AVKit
import ImageIO
import KSPlayer
import OSLog
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case tvGuide = "TV Guide"
  case movies = "Movies"
  case series = "Series"
  case favorites = "Favourites"
  case settings = "Settings"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .tvGuide: return "tv"
    case .movies: return "film"
    case .series: return "tv.inset.filled"
    case .favorites: return "heart.fill"
    case .settings: return "gearshape.fill"
    }
  }
}

enum ActiveSheet: Identifiable {
  case settings
  case playlistImport

  var id: Int {
    switch self {
    case .settings: return 1
    case .playlistImport: return 2
    }
  }
}

private struct ChannelCatalogSnapshot: Sendable {
  let visibleChannels: [Channel]
  let filteredChannels: [Channel]
  let categoryCounts: [ChannelCategory: Int]
  let availableCategories: [ChannelCategory]
}

struct ContentView: View {
  @AppStorage("playlistURL") private var playlistURL = ""
  @State private var credentials = PlaylistCredentials.shared
  @State private var profileStore = PlaylistProfileStore.shared
  @AppStorage("epgURL") private var epgURL = ""
  @State private var favoritesManager = FavoritesManager.shared
  @State private var hiddenChannelsManager = HiddenChannelsManager.shared
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var licenseManager = LicenseManager.shared
  @State private var playerEngine = PlayerEngineManager.shared
  @State private var isUsingKSPlayer = false
  @State private var videoValidationTask: Task<Void, Never>? = nil
  @State private var presentationSizeObserver: NSKeyValueObservation? = nil
  @State private var isPresentingPaywall = false
  @State private var channels: [Channel] = []
  @State private var movies: [Channel] = []
  @State private var series: [Channel] = []
  @State private var isLoadingVOD = false
  @State private var selectedChannelID: Channel.ID?
  @State private var activeDetailChannel: Channel?
  @State private var player: AVPlayer?
  @State private var streamErrorMessage: String? = nil
  @State private var isStreamLoading = false
  @State private var activeStatusObserver: NSKeyValueObservation? = nil
  @State private var playbackStallObserver: NSObjectProtocol? = nil
  @State private var playbackFailureObserver: NSObjectProtocol? = nil
  @State private var playbackRecoveryTask: Task<Void, Never>? = nil
  @State private var playbackRecoveryAttempts = 0
  @State private var selectedTab: AppTab = .tvGuide
  @State private var searchText = ""
  @State private var movieSearchText = ""
  @State private var seriesSearchText = ""
  @State private var favoritesSearchText = ""
  @State private var selectedCategory: ChannelCategory = .all
  @State private var activeSheet: ActiveSheet?
  @State private var isLoadingPlaylist = false
  @State private var playlistMessage: String?
  @State private var isPresentingFullScreenPlayer = false

  @State private var visibleChannels: [Channel] = []
  @State private var categoryCounts: [ChannelCategory: Int] = [:]
  @State private var availableCategories: [ChannelCategory] = [.all]
  @State private var filteredChannels: [Channel] = []
  @State private var searchDebounceTask: Task<Void, Never>?
  @State private var catalogRefreshTask: Task<Void, Never>?
  @State private var channelFilterTask: Task<Void, Never>?
  @State private var epgLoadTask: Task<Void, Never>?
  @State private var loadGeneration = UUID()

  private func updateVisibleChannels() {
    catalogRefreshTask?.cancel()
    let currentChannels = channels
    let hiddenURLs = hiddenChannelsManager.hiddenStreamURLs
    let favoriteURLs = favoritesManager.favoriteStreamURLs
    let category = selectedCategory
    let query = searchText

    catalogRefreshTask = Task {
      let work = Task.detached(priority: .userInitiated) {
        let visible = ChannelCatalog.visibleChannels(
          in: currentChannels,
          hiddenStreamURLs: hiddenURLs
        )

        var counts: [ChannelCategory: Int] = [.all: visible.count]
        var favoriteCount = 0
        var presentCategories = Set<ChannelCategory>()
        for channel in visible {
          counts[channel.category, default: 0] += 1
          presentCategories.insert(channel.category)
          if favoriteURLs.contains(channel.streamURLString) {
            favoriteCount += 1
          }
        }
        counts[.favorites] = favoriteCount

        var categories: [ChannelCategory] = [.all]
        if favoriteCount > 0 {
          categories.append(.favorites)
        }
        for item in ChannelCategory.allCases where item != .all && item != .favorites {
          if presentCategories.contains(item) {
            categories.append(item)
          }
        }

        let filtered = ChannelCatalog.filteredChannels(
          in: visible,
          category: category,
          favoriteStreamURLs: favoriteURLs,
          query: query
        )
        return ChannelCatalogSnapshot(
          visibleChannels: visible,
          filteredChannels: filtered,
          categoryCounts: counts,
          availableCategories: categories
        )
      }
      let snapshot = await withTaskCancellationHandler {
        await work.value
      } onCancel: {
        work.cancel()
      }

      guard !Task.isCancelled else { return }
      visibleChannels = snapshot.visibleChannels
      filteredChannels = snapshot.filteredChannels
      categoryCounts = snapshot.categoryCounts
      availableCategories = snapshot.availableCategories
    }
  }

  private func updateFilteredChannels() {
    channelFilterTask?.cancel()
    let currentChannels = visibleChannels
    let category = selectedCategory
    let favoriteURLs = favoritesManager.favoriteStreamURLs
    let query = searchText
    channelFilterTask = Task {
      let work = Task.detached(priority: .userInitiated) {
        ChannelCatalog.filteredChannels(
          in: currentChannels,
          category: category,
          favoriteStreamURLs: favoriteURLs,
          query: query
        )
      }
      let filtered = await withTaskCancellationHandler {
        await work.value
      } onCancel: {
        work.cancel()
      }
      guard !Task.isCancelled else { return }
      filteredChannels = filtered
    }
  }

  private func queueSearchFilter() {
    searchDebounceTask?.cancel()
    searchDebounceTask = Task {
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      updateFilteredChannels()
    }
  }

  private var selectedChannel: Channel? {
    if let activeDetailChannel {
      return activeDetailChannel
    }
    if let id = selectedChannelID {
      return channels.first { $0.id == id } ?? movies.first { $0.id == id }
        ?? series.first { $0.id == id }
    }
    return nil
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      TipTVTheme.contentBackground.ignoresSafeArea()

      // Main Tab View Content
      Group {
        if let activeDetailChannel {
          ChannelDetailView(
            channel: activeDetailChannel,
            allChannels: channels,
            player: player,
            isUsingKSPlayer: isUsingKSPlayer,
            errorMessage: streamErrorMessage,
            isLoadingStream: isStreamLoading,
            isPresentedFullScreen: isPresentingFullScreenPlayer,
            onSelectChannel: selectChannel,
            onOpenFullScreen: {
              if (activeDetailChannel.isMovie || activeDetailChannel.isSeries)
                && !activeDetailChannel.streamURLString.lowercased().contains(".mkv")
              {
                if !isUsingKSPlayer && player == nil {
                  startPlaybackForChannel(activeDetailChannel)
                }
              }
              isPresentingFullScreenPlayer = true
            },
            onBack: {
              stopMoviePlayer()
              withAnimation(.easeInOut(duration: 0.25)) {
                self.activeDetailChannel = nil
              }
            },
            onRetry: {
              if !activeDetailChannel.isVOD {
                selectChannel(activeDetailChannel)
              }
            },
            onTogglePlayerEngine: {
              togglePlayerEngineForActiveChannel()
            }
          )
          .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
          tabContent
        }
      }

      // Bottom Navigation Overlay
      VStack(spacing: 0) {
        // Mini Player Bar (floats directly above tab bar if active and not in detail)
        if let selectedChannel, activeDetailChannel == nil, player != nil || isUsingKSPlayer {
          MiniPlayerBar(
            channel: selectedChannel,
            player: player,
            isUsingKSPlayer: isUsingKSPlayer,
            onTap: {
              withAnimation(.easeInOut(duration: 0.25)) {
                activeDetailChannel = selectedChannel
              }
            },
            onClose: stopPlayback
          )
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Custom Bottom Tab Bar
        BottomTabBar(selectedTab: $selectedTab) { tab in
          if activeDetailChannel != nil {
            stopMoviePlayer()
            withAnimation(.easeInOut(duration: 0.2)) {
              activeDetailChannel = nil
            }
          }
          selectedTab = tab
          if (tab == .movies && movies.isEmpty) || (tab == .series && series.isEmpty) {
            Task {
              await loadVODContent()
            }
          }
        }
      }
    }
    .fullScreenOrSheetCover(isPresented: $isPresentingFullScreenPlayer) {
      if let activeChannel = activeDetailChannel ?? selectedChannel {
        FullScreenPlayerView(
          channel: activeChannel,
          allChannels: filteredChannels.isEmpty ? channels : filteredChannels,
          player: player,
          isUsingKSPlayer: isUsingKSPlayer,
          onSelectChannel: selectChannel,
          onDismiss: {
            isPresentingFullScreenPlayer = false
            if activeChannel.isMovie {
              stopMoviePlayer()
            }
          },
          onStop: stopPlayback,
          onTogglePlayerEngine: {
            togglePlayerEngineForActiveChannel()
          }
        )
      }
    }
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .settings:
        NavigationStack {
          SettingsView(
            playlistURL: $playlistURL,
            username: $credentials.username,
            epgURL: $epgURL,
            totalChannels: visibleChannels.count,
            allChannels: channels,
            onReload: {
              Task {
                await loadPlaylist()
              }
            },
            onDelete: {
              deletePlaylist()
              activeSheet = nil
            },
            onOpenImporter: {
              activeSheet = .playlistImport
            },
            onSelectProfile: selectProfile
          )
          .inlineNavigationBarTitle()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") {
                activeSheet = nil
              }
              .font(.system(size: 15, weight: .semibold, design: .rounded))
              .foregroundStyle(TipTVTheme.aqua)
            }
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .tint(themeManager.accent)
        .preferredColorScheme(.dark)

      case .playlistImport:
        PlaylistImportView(
          playlistURL: $playlistURL,
          username: $credentials.username,
          password: $credentials.password,
          epgURL: $epgURL,
          isLoading: isLoadingPlaylist,
          message: playlistMessage,
          loadPlaylist: {
            await loadPlaylist()
            if playlistMessage == nil || playlistMessage?.contains("loaded") == true {
              activeSheet = nil
            }
          },
          deletePlaylist: {
            deletePlaylist()
            activeSheet = nil
          }
        )
      }
    }
    .task {
      guard channels.isEmpty, !playlistURL.isEmpty else { return }
      if await restoreCachedContent() == false {
        await loadPlaylist()
      }
    }
    .tint(themeManager.accent)
    .preferredColorScheme(.dark)
    .sheet(isPresented: $isPresentingPaywall) {
      PaywallView(onDismiss: nil)
    }
    .onAppear {
      if !licenseManager.canAccessApp {
        isPresentingPaywall = true
      }
      updateVisibleChannels()
    }
    .onChange(of: selectedCategory) { _, _ in
      updateFilteredChannels()
    }
    .onChange(of: searchText) { _, _ in
      queueSearchFilter()
    }
    .onChange(of: favoritesManager.favoriteStreamURLs) { _, _ in
      updateVisibleChannels()
    }
    .onChange(of: hiddenChannelsManager.hiddenStreamURLs) { _, _ in
      updateVisibleChannels()
    }
    .onDisappear {
      catalogRefreshTask?.cancel()
      searchDebounceTask?.cancel()
      channelFilterTask?.cancel()
      epgLoadTask?.cancel()
      resetPlaybackRecovery()
    }
  }

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .tvGuide:
      NavigationStack {
        ChannelLibraryView(
          channels: filteredChannels,
          totalChannelCount: visibleChannels.count,
          categories: availableCategories,
          categoryCounts: categoryCounts,
          selectedCategory: $selectedCategory,
          selectedChannelID: $selectedChannelID,
          searchText: $searchText,
          isLoading: isLoadingPlaylist,
          onSelectChannel: selectChannel,
          openPlaylistImporter: { activeSheet = .playlistImport },
          reloadPlaylist: {
            Task {
              await loadPlaylist()
            }
          },
          deletePlaylist: deletePlaylist
        )
      }
      .padding(.bottom, 68)

    case .movies:
      NavigationStack {
        MoviesCatalogView(
          items: movies,
          title: "Movies",
          isLoading: isLoadingVOD,
          searchText: $movieSearchText,
          onSelectChannel: { channel in
            let movieItem = Channel(
              id: channel.id,
              name: channel.name,
              uniformName: channel.uniformName,
              group: channel.group,
              logoURL: channel.logoURL,
              streamURL: channel.streamURL,
              streamURLString: channel.streamURLString,
              category: .movies
            )
            selectChannel(movieItem)
          },
          onReload: {
            Task {
              await loadVODContent(forceRefresh: true)
            }
          }
        )
      }
      .padding(.bottom, 68)

    case .series:
      NavigationStack {
        MoviesCatalogView(
          items: series,
          title: "Series",
          isLoading: isLoadingVOD,
          searchText: $seriesSearchText,
          onSelectChannel: selectChannel,
          onReload: {
            Task {
              await loadVODContent(forceRefresh: true)
            }
          }
        )
      }
      .padding(.bottom, 68)

    case .favorites:
      NavigationStack {
        FavoritesCatalogView(
          channels: visibleChannels,
          movies: movies,
          series: series,
          baseURL: playlistURL,
          username: credentials.username,
          password: credentials.password,
          searchText: $favoritesSearchText,
          onSelectChannel: selectChannel,
          onSelectMovie: { movieItem in
            selectChannel(movieItem)
          },
          onPlayEpisode: { epChannel in
            selectChannel(epChannel)
          }
        )
      }
      .padding(.bottom, 68)

    case .settings:
      SettingsView(
        playlistURL: $playlistURL,
        username: $credentials.username,
        epgURL: $epgURL,
        totalChannels: visibleChannels.count,
        allChannels: channels,
        onReload: {

          Task {
            await loadPlaylist()
          }
        },
        onDelete: deletePlaylist,
        onOpenImporter: { activeSheet = .playlistImport },
        onSelectProfile: selectProfile
      )
      .padding(.bottom, 68)
    }
  }

  private func selectChannel(_ channel: Channel) {
    guard licenseManager.canAccessApp else {
      isPresentingPaywall = true
      return
    }
    selectedChannelID = channel.id
    RecentChannelsManager.shared.recordChannel(channel)

    videoValidationTask?.cancel()
    videoValidationTask = nil
    presentationSizeObserver?.invalidate()
    presentationSizeObserver = nil
    player?.pause()
    player = nil
    streamErrorMessage = nil
    isStreamLoading = true
    activeStatusObserver?.invalidate()
    activeStatusObserver = nil
    resetPlaybackRecovery()

    // If this is a movie or series or selected on the movies/series tab, DO NOT load or start playing in that screen.
    // Just present the detail screen showing the picture/thumbnail. Playback only begins in full screen.
    let isKnownMovie = channel.isMovie || channel.category == .movies || selectedTab == .movies
    let isKnownSeries = channel.isSeries || channel.category == .series || selectedTab == .series

    if isKnownMovie || isKnownSeries {
      isUsingKSPlayer = false
      streamErrorMessage = nil
      isStreamLoading = false
      let vodChannel = Channel(
        id: channel.id,
        name: channel.name,
        uniformName: channel.uniformName,
        group: channel.group,
        logoURL: channel.logoURL,
        streamURL: channel.streamURL,
        streamURLString: channel.streamURLString,
        category: isKnownSeries ? .series : .movies
      )
      withAnimation(.easeInOut(duration: 0.25)) {
        activeDetailChannel = vodChannel
      }
      return
    }

    // Check if stream should use FFmpeg (MKV, setting preference, or sound-only MPEG-2 broadcast detection)
    if playerEngine.shouldRunFFmpeg(for: channel) {
      isUsingKSPlayer = true
      streamErrorMessage = nil
      isStreamLoading = false
      withAnimation(.easeInOut(duration: 0.25)) {
        activeDetailChannel = channel
      }
      return
    }

    isUsingKSPlayer = false
    startPlaybackForChannel(channel)
    withAnimation(.easeInOut(duration: 0.25)) {
      activeDetailChannel = channel
    }
  }

  private func togglePlayerEngineForActiveChannel() {
    guard let channel = activeDetailChannel ?? selectedChannel else { return }
    videoValidationTask?.cancel()
    videoValidationTask = nil
    let newIsFFmpeg = playerEngine.toggleEngine(for: channel, currentIsFFmpeg: isUsingKSPlayer)
    if newIsFFmpeg {
      resetPlaybackRecovery()
      player?.pause()
      player = nil
      streamErrorMessage = nil
      isStreamLoading = false
      withAnimation(.easeInOut(duration: 0.25)) {
        isUsingKSPlayer = true
      }
    } else {
      isUsingKSPlayer = false
      startPlaybackForChannel(channel)
    }
  }

  private func verifyVideoPlayback(for item: AVPlayerItem, channel: Channel) {
    videoValidationTask?.cancel()
    presentationSizeObserver?.invalidate()

    // If video dimensions are already non-zero, video is confirmed
    if item.presentationSize.width > 0 && item.presentationSize.height > 0 {
      return
    }

    // Non-blocking KVO observation on presentationSize.
    // As soon as video dimensions are decoded, cancel validation task and clear observer.
    presentationSizeObserver = item.observe(\.presentationSize, options: [.new]) {
      observedItem, _ in
      if observedItem.presentationSize.width > 0 && observedItem.presentationSize.height > 0 {
        Task { @MainActor in
          self.videoValidationTask?.cancel()
          self.videoValidationTask = nil
          self.presentationSizeObserver?.invalidate()
          self.presentationSizeObserver = nil
        }
      }
    }

    // Only evaluate broadcast streams (.ts or /live/) where MPEG-2 sound-only occurs
    guard playerEngine.enginePreference == .auto else { return }
    let lowerURL = channel.streamURLString.lowercased()
    guard lowerURL.contains(".ts") || lowerURL.contains("/live/") else { return }

    videoValidationTask = Task { @MainActor in
      // Allow 4.5 seconds for video headers and keyframes to negotiate
      try? await Task.sleep(nanoseconds: 4_500_000_000)
      guard !Task.isCancelled else { return }
      guard self.player?.currentItem === item, !self.isUsingKSPlayer else { return }

      let isPlaying = (self.player?.timeControlStatus == .playing || (self.player?.rate ?? 0) > 0)
      let isStillZeroSize = (item.presentationSize.width <= 0 || item.presentationSize.height <= 0)

      // If audio has been playing actively for 4.5s but video presentation size remains 0x0:
      if isPlaying && isStillZeroSize {
        #if DEBUG
          AppLog.playback.notice(
            "Sound-only broadcast detected for \(channel.uniformName, privacy: .public). Switching to FFmpeg."
          )
        #endif
        self.playerEngine.markChannelRequiresFFmpeg(channel)
        self.player?.pause()
        self.player = nil
        self.activeStatusObserver?.invalidate()
        self.activeStatusObserver = nil
        self.resetPlaybackRecovery()
        self.presentationSizeObserver?.invalidate()
        self.presentationSizeObserver = nil
        withAnimation(.easeInOut(duration: 0.25)) {
          self.isUsingKSPlayer = true
        }
      }
    }
  }

  private func startPlaybackForChannel(_ channel: Channel) {
    let originalURL = channel.streamURL
    let originalStr = originalURL.absoluteString
    let originalLower = originalStr.lowercased()

    let primaryURL: URL
    let fallbackURL: URL?

    if originalLower.contains("/live/") {
      if originalLower.hasSuffix(".ts") || originalLower.contains(".ts?") {
        let m3u8Str = originalStr.replacingOccurrences(of: ".ts", with: ".m3u8")
        primaryURL = URL(string: m3u8Str) ?? originalURL
        fallbackURL = originalURL
      } else if originalLower.hasSuffix(".m3u8") || originalLower.contains(".m3u8?") {
        let tsStr = originalStr.replacingOccurrences(of: ".m3u8", with: ".ts")
        primaryURL = originalURL
        fallbackURL = URL(string: tsStr)
      } else {
        primaryURL = originalURL
        fallbackURL = nil
      }
    } else if originalLower.contains("/movie/") {
      if originalLower.hasSuffix(".mkv") {
        let mp4Str = originalStr.replacingOccurrences(of: ".mkv", with: ".mp4")
        primaryURL = originalURL
        fallbackURL = URL(string: mp4Str)
      } else if originalLower.hasSuffix(".mp4") {
        let mkvStr = originalStr.replacingOccurrences(of: ".mp4", with: ".mkv")
        primaryURL = originalURL
        fallbackURL = URL(string: mkvStr)
      } else {
        primaryURL = originalURL
        fallbackURL = nil
      }
    } else if originalLower.contains("/series/") {
      if originalLower.hasSuffix(".mkv") {
        let mp4Str = originalStr.replacingOccurrences(of: ".mkv", with: ".mp4")
        primaryURL = originalURL
        fallbackURL = URL(string: mp4Str)
      } else if originalLower.hasSuffix(".mp4") {
        let mkvStr = originalStr.replacingOccurrences(of: ".mp4", with: ".mkv")
        primaryURL = originalURL
        fallbackURL = URL(string: mkvStr)
      } else {
        primaryURL = originalURL
        fallbackURL = nil
      }
    } else {
      primaryURL = originalURL
      fallbackURL = nil
    }

    let newPlayer = makePlayer(for: primaryURL, fallbackURL: fallbackURL, channel: channel)
    player = newPlayer
    newPlayer.play()
  }

  private func stopMoviePlayer() {
    videoValidationTask?.cancel()
    videoValidationTask = nil
    presentationSizeObserver?.invalidate()
    presentationSizeObserver = nil
    activeStatusObserver?.invalidate()
    activeStatusObserver = nil
    resetPlaybackRecovery()
    streamErrorMessage = nil
    isStreamLoading = false
    player?.pause()
    player = nil
    isUsingKSPlayer = false
  }

  private func makePlayer(for url: URL, fallbackURL: URL? = nil, channel: Channel) -> AVPlayer {
    let headers: [String: String] = [
      "User-Agent": XtreamService.defaultUserAgent
    ]

    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let item = AVPlayerItem(asset: asset)
    // Fast start buffer configuration
    item.preferredForwardBufferDuration = 4.0
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    item.automaticallyPreservesTimeOffsetFromLive = true

    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true
    player.preventsDisplaySleepDuringVideoPlayback = true
    player.automaticallyWaitsToMinimizeStalling = true

    // KVO observer on item.status to handle fast startup, fallbacks, and error reporting
    activeStatusObserver?.invalidate()
    activeStatusObserver = item.observe(\.status, options: [.initial, .new]) {
      [weak player] currentItem, _ in
      Task { @MainActor [weak player] in
        guard let player else { return }
        switch currentItem.status {
        case .readyToPlay:
          self.playbackRecoveryTask?.cancel()
          self.playbackRecoveryTask = nil
          self.playbackRecoveryAttempts = 0
          self.isStreamLoading = false
          self.streamErrorMessage = nil
          player.play()
          if let ch = self.activeDetailChannel ?? self.selectedChannel {
            self.verifyVideoPlayback(for: currentItem, channel: ch)
          }
        case .failed:
          let errMessage = currentItem.error?.localizedDescription ?? "Unknown format error"
          AppLog.playback.error(
            "AVPlayerItem failed for \(url.absoluteString, privacy: .private(mask: .hash)): \(errMessage, privacy: .public)"
          )
          // Try fallback URL in native player first (e.g. .ts when .m3u8 failed)
          if let fallbackURL, fallbackURL != url {
            AppLog.playback.notice(
              "Attempting fallback stream URL: \(fallbackURL.absoluteString, privacy: .private(mask: .hash))"
            )
            let fallbackAsset = AVURLAsset(
              url: fallbackURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let fallbackItem = AVPlayerItem(asset: fallbackAsset)
            fallbackItem.preferredForwardBufferDuration = 4.0
            fallbackItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            fallbackItem.automaticallyPreservesTimeOffsetFromLive = true

            self.activeStatusObserver?.invalidate()
            self.activeStatusObserver = fallbackItem.observe(\.status, options: [.new]) {
              [weak player] fbItem, _ in
              guard let player else { return }
              Task { @MainActor in
                if fbItem.status == .readyToPlay {
                  self.playbackRecoveryTask?.cancel()
                  self.playbackRecoveryTask = nil
                  self.playbackRecoveryAttempts = 0
                  self.isStreamLoading = false
                  self.streamErrorMessage = nil
                  player.play()
                  if let ch = self.activeDetailChannel ?? self.selectedChannel {
                    self.verifyVideoPlayback(for: fbItem, channel: ch)
                  }
                } else if fbItem.status == .failed {
                  // Both primary and fallback URLs failed with native player
                  if let ch = self.activeDetailChannel ?? self.selectedChannel,
                    !self.isUsingKSPlayer,
                    self.playerEngine.enginePreference != .native
                  {
                    AppLog.playback.notice(
                      "Native player failed for both URLs; attempting FFmpeg for \(ch.uniformName, privacy: .public)"
                    )
                    self.player?.pause()
                    self.player = nil
                    self.resetPlaybackRecovery()
                    withAnimation(.easeInOut(duration: 0.25)) {
                      self.isUsingKSPlayer = true
                      self.streamErrorMessage = nil
                      self.isStreamLoading = false
                    }
                    return
                  }

                  self.isStreamLoading = false
                  let isMKV =
                    url.pathExtension.lowercased() == "mkv"
                    || fallbackURL.pathExtension.lowercased() == "mkv"
                    || url.absoluteString.contains(".mkv")
                  if isMKV {
                    self.streamErrorMessage = "MKV Format (Requires External Player)"
                  } else {
                    self.streamErrorMessage = "Stream unavailable from provider"
                  }
                }
              }
            }
            player.replaceCurrentItem(with: fallbackItem)
            self.observePlaybackRecovery(for: fallbackItem, channel: channel)
            player.play()
          } else {
            // No fallback URL; attempt FFmpeg if allowed
            if let ch = self.activeDetailChannel ?? self.selectedChannel,
              !self.isUsingKSPlayer,
              self.playerEngine.enginePreference != .native
            {
              AppLog.playback.notice(
                "Native player failed; switching to FFmpeg for \(ch.uniformName, privacy: .public)"
              )
              self.player?.pause()
              self.player = nil
              self.resetPlaybackRecovery()
              withAnimation(.easeInOut(duration: 0.25)) {
                self.isUsingKSPlayer = true
                self.streamErrorMessage = nil
                self.isStreamLoading = false
              }
              return
            }

            self.isStreamLoading = false
            let isMKV =
              url.pathExtension.lowercased() == "mkv" || url.absoluteString.contains(".mkv")
            if isMKV {
              self.streamErrorMessage = "MKV Format (Requires External Player)"
            } else {
              self.streamErrorMessage = "Stream unavailable or unsupported format"
            }
          }
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    observePlaybackRecovery(for: item, channel: channel)

    return player
  }

  private func observePlaybackRecovery(for item: AVPlayerItem, channel: Channel) {
    if let playbackStallObserver {
      NotificationCenter.default.removeObserver(playbackStallObserver)
    }
    if let playbackFailureObserver {
      NotificationCenter.default.removeObserver(playbackFailureObserver)
    }

    playbackStallObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.playbackStalledNotification,
      object: item,
      queue: .main
    ) { _ in
      Task { @MainActor in
        self.schedulePlaybackRecovery(for: channel, expectedItem: item)
      }
    }

    playbackFailureObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { notification in
      let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
      #if DEBUG
        AppLog.playback.error(
          "Playback interrupted for \(channel.uniformName, privacy: .public): \(error?.localizedDescription ?? "unknown error", privacy: .public)"
        )
      #endif
      Task { @MainActor in
        self.schedulePlaybackRecovery(for: channel, expectedItem: item)
      }
    }
  }

  private func schedulePlaybackRecovery(for channel: Channel, expectedItem: AVPlayerItem) {
    guard player?.currentItem === expectedItem,
      selectedChannelID == channel.id,
      !isUsingKSPlayer
    else { return }

    playbackRecoveryTask?.cancel()
    playbackRecoveryAttempts += 1
    let attempt = playbackRecoveryAttempts
    isStreamLoading = true
    streamErrorMessage = PlaybackRecoveryPolicy.statusMessage(forAttempt: attempt)

    playbackRecoveryTask = Task { @MainActor in
      do {
        try await Task.sleep(for: PlaybackRecoveryPolicy.delay(forAttempt: attempt))
      } catch {
        return
      }
      guard !Task.isCancelled,
        self.selectedChannelID == channel.id,
        self.player?.currentItem === expectedItem
      else { return }

      if self.player?.timeControlStatus == .playing {
        self.playbackRecoveryAttempts = 0
        self.isStreamLoading = false
        self.streamErrorMessage = nil
        return
      }

      if attempt == 1 {
        self.player?.play()
        do {
          try await Task.sleep(for: .seconds(2))
        } catch {
          return
        }
        guard !Task.isCancelled, self.selectedChannelID == channel.id else { return }
        let action = PlaybackRecoveryPolicy.action(
          forAttempt: attempt,
          isPlaying: self.player?.timeControlStatus == .playing,
          isVOD: channel.isVOD,
          backupPlayerAllowed: self.playerEngine.enginePreference != .native
        )
        if action == .recovered {
          self.playbackRecoveryAttempts = 0
          self.isStreamLoading = false
          self.streamErrorMessage = nil
        } else if action == .reloadNative {
          self.startPlaybackForChannel(channel)
        } else {
          self.isStreamLoading = false
          self.streamErrorMessage = "Playback was interrupted. Tap Retry to continue."
        }
        return
      }

      let action = PlaybackRecoveryPolicy.action(
        forAttempt: attempt,
        isPlaying: false,
        isVOD: channel.isVOD,
        backupPlayerAllowed: self.playerEngine.enginePreference != .native
      )
      if action == .switchToBackup {
        self.player?.pause()
        self.player = nil
        self.resetPlaybackRecovery()
        self.isUsingKSPlayer = true
        self.isStreamLoading = false
        self.streamErrorMessage = nil
      } else {
        self.isStreamLoading = false
        self.streamErrorMessage = "The stream stopped responding. Tap Retry to reconnect."
      }
    }
  }

  private func resetPlaybackRecovery() {
    playbackRecoveryTask?.cancel()
    playbackRecoveryTask = nil
    playbackRecoveryAttempts = 0
    if let playbackStallObserver {
      NotificationCenter.default.removeObserver(playbackStallObserver)
    }
    if let playbackFailureObserver {
      NotificationCenter.default.removeObserver(playbackFailureObserver)
    }
    playbackStallObserver = nil
    playbackFailureObserver = nil
  }

  private func stopPlayback() {
    videoValidationTask?.cancel()
    videoValidationTask = nil
    presentationSizeObserver?.invalidate()
    presentationSizeObserver = nil
    activeStatusObserver?.invalidate()
    activeStatusObserver = nil
    resetPlaybackRecovery()
    streamErrorMessage = nil
    isStreamLoading = false
    player?.pause()
    player = nil
    isUsingKSPlayer = false
    selectedChannelID = nil
    activeDetailChannel = nil
    isPresentingFullScreenPlayer = false
  }

  private func loadVODContent(forceRefresh: Bool = false) async {
    guard !isLoadingVOD else { return }
    let generation = loadGeneration
    let cacheKey = playlistCacheKey
    let baseURL = playlistURL

    let username = credentials.username
    let password = credentials.password
    isLoadingVOD = true
    defer {
      if loadGeneration == generation {
        isLoadingVOD = false
      }
    }

    if !forceRefresh {
      async let cachedMovies = PlaylistCacheManager.shared.loadCachedMovies(for: cacheKey)
      async let cachedSeries = PlaylistCacheManager.shared.loadCachedSeries(for: cacheKey)
      if let cachedMovieItems = await cachedMovies,
        let cachedSeriesItems = await cachedSeries
      {
        guard loadGeneration == generation else { return }
        movies = cachedMovieItems
        series = cachedSeriesItems
        return
      }
    }

    guard !username.isEmpty && !password.isEmpty else {
      let currentChannels = channels
      let (m, s) = await Task.detached(priority: .userInitiated) {
        let movies = currentChannels.filter { ch in
          let path = ch.streamURL.path.lowercased()
          let group = ch.group?.lowercased() ?? ""
          return path.hasSuffix(".mp4") || path.hasSuffix(".mkv") || group.contains("vod")
            || (group.contains("movie") && !group.contains("live"))
        }.map { ch in
          if ch.category == .movies { return ch }
          return Channel(
            id: ch.id,
            name: ch.name,
            uniformName: ch.uniformName,
            group: ch.group,
            logoURL: ch.logoURL,
            streamURL: ch.streamURL,
            streamURLString: ch.streamURLString,
            category: .movies
          )
        }
        let series = currentChannels.compactMap { ch -> Channel? in
          let group = ch.group?.lowercased() ?? ""
          guard
            group.contains("series") || group.contains("season") || group.contains("boxset")
              || ch.category == .series
          else {
            return nil
          }
          return Channel(
            id: ch.id,
            name: ch.name,
            uniformName: ch.uniformName,
            group: ch.group,
            logoURL: ch.logoURL,
            streamURL: ch.streamURL,
            streamURLString: ch.streamURLString,
            category: .series
          )
        }
        return (movies, series)
      }.value
      guard loadGeneration == generation else { return }
      self.movies = m
      self.series = s
      await PlaylistCacheManager.shared.saveMovies(m, for: cacheKey)
      await PlaylistCacheManager.shared.saveSeries(s, for: cacheKey)
      return
    }

    // Fetch movies first and update UI immediately so user gets content right away
    let m = await XtreamService.fetchXtreamVOD(
      baseURL: baseURL, username: username, password: password)
    guard loadGeneration == generation else { return }
    self.movies = m
    await PlaylistCacheManager.shared.saveMovies(m, for: cacheKey)
    guard loadGeneration == generation else { return }

    // Then fetch series sequentially to prevent simultaneous RAM spikes
    let s = await XtreamService.fetchXtreamSeries(
      baseURL: baseURL, username: username, password: password)
    guard loadGeneration == generation else { return }
    self.series = s
    await PlaylistCacheManager.shared.saveSeries(s, for: cacheKey)
  }

  private func loadPlaylist() async {
    guard !isLoadingPlaylist else { return }
    guard let url = validatedPlaylistURL else {
      playlistMessage = "Enter a valid HTTP or HTTPS playlist URL."
      return
    }

    let generation = loadGeneration
    let sourceURL = playlistURL
    let username = credentials.username
    let password = credentials.password
    let cacheKey = playlistCacheKey
    isLoadingPlaylist = true
    playlistMessage = "Connecting to your provider…"

    do {
      // 1. Check if this is an Xtream Codes server (server URL + username + password)
      if !username.isEmpty && !password.isEmpty {
        let isXtream = await XtreamService.isXtreamServer(
          baseURL: sourceURL,
          username: username,
          password: password
        )
        guard loadGeneration == generation else { return }
        if isXtream {
          playlistMessage = "Downloading live channels…"
          let xtreamChannels = try await XtreamService.fetchXtreamChannels(
            baseURL: sourceURL,
            username: username,
            password: password
          )
          guard loadGeneration == generation else { return }
          channels = xtreamChannels
          updateVisibleChannels()
          selectedCategory = .all
          playlistMessage = "\(xtreamChannels.count) channels loaded."
          await PlaylistCacheManager.shared.saveChannels(xtreamChannels, for: cacheKey)
          guard loadGeneration == generation else { return }
          persistCurrentProfile()
          loadProgrammeGuide(for: xtreamChannels, force: true)
          activeSheet = nil
          isLoadingPlaylist = false
          Task {
            await loadVODContent(forceRefresh: true)
          }
          return
        }
      }

      // 2. Standard M3U / M3U8 Playlist Stream Loader (Ultra-low RAM streaming via disk)
      var request = URLRequest(url: url)
      request.timeoutInterval = 45
      request.setValue(XtreamService.defaultUserAgent, forHTTPHeaderField: "User-Agent")

      if !username.isEmpty || !password.isEmpty {
        let credentialString = "\(username):\(password)"
        if let credentialData = credentialString.data(using: .utf8) {
          let base64Credential = credentialData.base64EncodedString()
          request.setValue("Basic \(base64Credential)", forHTTPHeaderField: "Authorization")
        }
      }

      let (tempFileURL, response) = try await URLSession.shared.download(for: request)
      defer { try? FileManager.default.removeItem(at: tempFileURL) }
      guard loadGeneration == generation else { return }

      guard let httpResponse = response as? HTTPURLResponse else {
        throw PlaylistError.unavailable
      }

      if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        throw PlaylistError.unauthorized
      }

      guard 200..<300 ~= httpResponse.statusCode else {
        throw PlaylistError.unavailable
      }

      playlistMessage = "Reading playlist…"
      let importedChannels = try await PlaylistParser.channels(fromFileURL: tempFileURL)
      guard loadGeneration == generation else { return }
      guard !importedChannels.isEmpty else {
        throw PlaylistError.noChannels
      }

      channels = importedChannels
      updateVisibleChannels()
      selectedCategory = .all
      playlistMessage = "\(importedChannels.count) channels loaded."
      await PlaylistCacheManager.shared.saveChannels(importedChannels, for: cacheKey)
      guard loadGeneration == generation else { return }
      persistCurrentProfile()
      loadProgrammeGuide(for: importedChannels, force: true)
      activeSheet = nil
    } catch {
      guard loadGeneration == generation else { return }
      if channels.isEmpty, await restoreCachedContent() {
        playlistMessage =
          "The provider could not be reached. Your saved channels are still available."
      } else {
        playlistMessage = "\(error.localizedDescription) Your existing channels were kept."
      }
    }

    if loadGeneration == generation {
      isLoadingPlaylist = false
    }
  }

  private func deletePlaylist() {
    stopPlayback()
    loadGeneration = UUID()
    isLoadingPlaylist = false
    isLoadingVOD = false
    let deletedCacheKey = playlistCacheKey
    let deletedProfileID = profileStore.selectedProfileID
    profileStore.deleteSelected()
    if let deletedProfileID {
      credentials.deletePassword(for: deletedProfileID)
    }

    if let replacement = profileStore.selectedProfile {
      playlistURL = replacement.playlistURL
      epgURL = replacement.epgURL
      credentials.username = replacement.username
      credentials.loadPassword(for: replacement.id)
    } else {
      playlistURL = ""
      epgURL = ""
      credentials.clear()
    }
    channels = []
    epgLoadTask?.cancel()
    EPGManager.shared.clearCache()
    updateVisibleChannels()
    movies = []
    series = []
    selectedChannelID = nil
    activeDetailChannel = nil
    selectedCategory = .all
    searchText = ""
    movieSearchText = ""
    seriesSearchText = ""
    favoritesSearchText = ""
    playlistMessage = nil
    Task {
      await PlaylistCacheManager.shared.clear(for: deletedCacheKey)
      if profileStore.selectedProfile != nil {
        if await restoreCachedContent() == false {
          await loadPlaylist()
        }
      }
    }
  }

  private func restoreCachedContent() async -> Bool {
    let generation = loadGeneration
    let cacheKey = playlistCacheKey
    guard let cachedChannels = await PlaylistCacheManager.shared.loadCachedChannels(for: cacheKey),
      loadGeneration == generation,
      !cachedChannels.isEmpty
    else {
      return false
    }

    channels = cachedChannels
    updateVisibleChannels()
    selectedCategory = .all
    playlistMessage = "\(cachedChannels.count) cached channels loaded."
    loadProgrammeGuide(for: cachedChannels)

    async let cachedMovies = PlaylistCacheManager.shared.loadCachedMovies(for: cacheKey)
    async let cachedSeries = PlaylistCacheManager.shared.loadCachedSeries(for: cacheKey)
    let restoredMovies = await cachedMovies ?? []
    let restoredSeries = await cachedSeries ?? []
    guard loadGeneration == generation else { return false }
    movies = restoredMovies
    series = restoredSeries
    return true
  }

  private func loadProgrammeGuide(for channels: [Channel], force: Bool = false) {
    epgLoadTask?.cancel()

    guard !channels.isEmpty, let url = resolvedEPGURL else {
      EPGManager.shared.clearCache()
      return
    }

    epgLoadTask = Task {
      await EPGManager.shared.load(from: url, channels: channels, force: force)
    }
  }

  private var resolvedEPGURL: URL? {
    let configuredURL = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: configuredURL),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      return url
    }

    guard !credentials.username.isEmpty, !credentials.password.isEmpty,
      var components = URLComponents(string: "\(XtreamService.cleanBaseURL(playlistURL))/xmltv.php")
    else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "username", value: credentials.username),
      URLQueryItem(name: "password", value: credentials.password),
    ]
    return components.url
  }

  private func persistCurrentProfile() {
    let profile: PlaylistProfile
    if let selected = profileStore.selectedProfile,
      selected.playlistURL == playlistURL
    {
      profileStore.updateSelected(
        playlistURL: playlistURL,
        username: credentials.username,
        epgURL: epgURL
      )
      profile = profileStore.selectedProfile ?? selected
    } else {
      profile = profileStore.save(
        name: URL(string: playlistURL)?.host ?? "My Playlist",
        playlistURL: playlistURL,
        username: credentials.username,
        epgURL: epgURL
      )
    }
    credentials.savePassword(for: profile.id)
  }

  private func selectProfile(_ profile: PlaylistProfile) {
    loadGeneration = UUID()
    isLoadingPlaylist = false
    isLoadingVOD = false
    epgLoadTask?.cancel()
    profileStore.select(profile)
    playlistURL = profile.playlistURL
    epgURL = profile.epgURL
    credentials.username = profile.username
    credentials.loadPassword(for: profile.id)
    channels = []
    movies = []
    series = []
    updateVisibleChannels()
    Task {
      if await restoreCachedContent() == false {
        await loadPlaylist()
      }
    }
  }

  private var validatedPlaylistURL: URL? {
    guard let url = URL(string: playlistURL),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return nil
    }

    return url
  }

  private var playlistCacheKey: String {
    "\(playlistURL)|\(credentials.username)"
  }
}

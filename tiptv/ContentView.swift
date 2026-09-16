//
//  ContentView.swift
//  tiptv
//

import AVFoundation
import AVKit
import ImageIO
import KSPlayer
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case tvGuide = "TV Guide"
    case movies = "Movies"
    case series = "Series"
    case more = "More"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .tvGuide: return "tv"
        case .movies: return "film"
        case .series: return "tv.inset.filled"
        case .more: return "ellipsis"
        }
    }
}

enum ActiveSheet: Identifiable {
    case search
    case settings
    case playlistImport

    var id: Int {
        switch self {
        case .search: return 1
        case .settings: return 2
        case .playlistImport: return 3
        }
    }
}

struct ContentView: View {
    @AppStorage("playlistURL") private var playlistURL = ""
    @AppStorage("playlistUsername") private var playlistUsername = ""
    @AppStorage("playlistPassword") private var playlistPassword = ""
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var hiddenChannelsManager = HiddenChannelsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var playerEngine = PlayerEngineManager.shared
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
    @State private var selectedTab: AppTab = .home
    @State private var searchText = ""
    @State private var selectedCategory: NetflixCategory = .all
    @State private var activeSheet: ActiveSheet?
    @State private var isLoadingPlaylist = false
    @State private var playlistMessage: String?
    @State private var isPresentingFullScreenPlayer = false

    @State private var visibleChannels: [Channel] = []
    @State private var categoryCounts: [NetflixCategory: Int] = [:]
    @State private var availableCategories: [NetflixCategory] = [.all]
    @State private var filteredChannels: [Channel] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    private func updateVisibleChannels() {
        let hidden = hiddenChannelsManager.hiddenStreamURLs
        if hidden.isEmpty {
            visibleChannels = channels
        } else {
            visibleChannels = channels.filter { !hidden.contains($0.streamURLString) }
        }
        updateCategoryState()
        updateFilteredChannels()
    }

    private func updateCategoryState() {
        var counts: [NetflixCategory: Int] = [.all: visibleChannels.count]
        var favCount = 0
        let favURLs = favoritesManager.favoriteStreamURLs
        var presentCats = Set<NetflixCategory>()

        for ch in visibleChannels {
            let cat = ch.category
            counts[cat, default: 0] += 1
            presentCats.insert(cat)
            if favURLs.contains(ch.streamURLString) {
                favCount += 1
            }
        }
        counts[.favorites] = favCount

        var categories: [NetflixCategory] = [.all]
        if favCount > 0 {
            categories.append(.favorites)
        }
        for cat in NetflixCategory.allCases where cat != .all && cat != .favorites {
            if presentCats.contains(cat) {
                categories.append(cat)
            }
        }
        categoryCounts = counts
        availableCategories = categories
    }

    private func updateFilteredChannels() {
        let baseList: [Channel]
        if selectedCategory == .all {
            baseList = visibleChannels
        } else if selectedCategory == .favorites {
            let favURLs = favoritesManager.favoriteStreamURLs
            baseList = visibleChannels.filter { favURLs.contains($0.streamURLString) }
        } else {
            let cat = selectedCategory
            baseList = visibleChannels.filter { $0.category == cat }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            filteredChannels = baseList
            return
        }

        if baseList.count > 2500 {
            Task.detached(priority: .userInitiated) {
                let filtered = baseList.filter { $0.searchKey.contains(q) }
                await MainActor.run {
                    self.filteredChannels = filtered
                }
            }
        } else {
            filteredChannels = baseList.filter { $0.searchKey.contains(q) }
        }
    }

    private func queueSearchFilter() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            updateFilteredChannels()
        }
    }

    private var selectedChannel: Channel? {
        if let activeDetailChannel {
            return activeDetailChannel
        }
        if let id = selectedChannelID {
            return channels.first { $0.id == id } ?? movies.first { $0.id == id } ?? series.first { $0.id == id }
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tiptvTheme.contentBackground.ignoresSafeArea()

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
                            if (activeDetailChannel.isMovie || activeDetailChannel.isSeries) && !activeDetailChannel.streamURLString.lowercased().contains(".mkv") {
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
                if let selectedChannel, activeDetailChannel == nil, (player != nil || isUsingKSPlayer) {
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
            case .search:
                ChannelSearchView(
                    channels: visibleChannels,
                    onSelectChannel: selectChannel
                )
            case .settings:
                NavigationStack {
                    SettingsView(
                        playlistURL: $playlistURL,
                        username: $playlistUsername,
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
                        }
                    )
                    .inlineNavigationBarTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                activeSheet = nil
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(tiptvTheme.aqua)
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
                    username: $playlistUsername,
                    password: $playlistPassword,
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
            await loadPlaylist()
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
        .onReceive(favoritesManager.$favoriteStreamURLs) { _ in
            updateCategoryState()
            if selectedCategory == .favorites {
                updateFilteredChannels()
            }
        }
        .onReceive(hiddenChannelsManager.$hiddenStreamURLs) { _ in
            updateVisibleChannels()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(
                channels: visibleChannels,
                allChannels: channels,
                onSelectChannel: selectChannel,
                onSelectCategory: { category in
                    selectedCategory = category
                    withAnimation {
                        selectedTab = .tvGuide
                    }
                },
                onReloadPlaylist: {
                    Task {
                        await loadPlaylist()
                    }
                },
                onDeletePlaylist: deletePlaylist,
                onAddPlaylist: {
                    activeSheet = .playlistImport
                }
            )
            .padding(.bottom, 68)

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
            MoviesCatalogView(
                items: movies,
                title: "Movies",
                isLoading: isLoadingVOD,
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
                        await loadVODContent()
                    }
                }
            )
            .padding(.bottom, 68)

        case .series:
            MoviesCatalogView(
                items: series,
                title: "Series",
                isLoading: isLoadingVOD,
                onSelectChannel: selectChannel,
                onReload: {
                    Task {
                        await loadVODContent()
                    }
                }
            )
            .padding(.bottom, 68)

        case .more:
            SettingsView(
                playlistURL: $playlistURL,
                username: $playlistUsername,
                totalChannels: visibleChannels.count,
                allChannels: channels,
                onReload: {
                    Task {
                        await loadPlaylist()
                    }
                },
                onDelete: deletePlaylist,
                onOpenImporter: { activeSheet = .playlistImport }
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
        presentationSizeObserver = item.observe(\.presentationSize, options: [.new]) { observedItem, _ in
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
                print("[PlayerEngine] Sound-only broadcast detected for \(channel.uniformName). Switching to FFmpeg engine.")
                #endif
                self.playerEngine.markChannelRequiresFFmpeg(channel)
                self.player?.pause()
                self.player = nil
                self.activeStatusObserver?.invalidate()
                self.activeStatusObserver = nil
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

        let newPlayer = makePlayer(for: primaryURL, fallbackURL: fallbackURL)
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
        streamErrorMessage = nil
        isStreamLoading = false
        player?.pause()
        player = nil
        isUsingKSPlayer = false
    }

    private func makePlayer(for url: URL, fallbackURL: URL? = nil) -> AVPlayer {
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
        activeStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak player] currentItem, _ in
            Task { @MainActor [weak player] in
                guard let player else { return }
                switch currentItem.status {
                case .readyToPlay:
                    self.isStreamLoading = false
                    self.streamErrorMessage = nil
                    player.play()
                    if let ch = self.activeDetailChannel ?? self.selectedChannel {
                        self.verifyVideoPlayback(for: currentItem, channel: ch)
                    }
                case .failed:
                    let errMessage = currentItem.error?.localizedDescription ?? "Unknown format error"
                    print("AVPlayerItem failed for \(url): \(errMessage)")
                    // Try fallback URL in native player first (e.g. .ts when .m3u8 failed)
                    if let fallbackURL, fallbackURL != url {
                        print("Attempting fallback stream URL: \(fallbackURL)")
                        let fallbackAsset = AVURLAsset(url: fallbackURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                        let fallbackItem = AVPlayerItem(asset: fallbackAsset)
                        fallbackItem.preferredForwardBufferDuration = 4.0
                        fallbackItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                        fallbackItem.automaticallyPreservesTimeOffsetFromLive = true

                        self.activeStatusObserver?.invalidate()
                        self.activeStatusObserver = fallbackItem.observe(\.status, options: [.new]) { [weak player] fbItem, _ in
                            guard let player else { return }
                            Task { @MainActor in
                                if fbItem.status == .readyToPlay {
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
                                       self.playerEngine.enginePreference != .native {
                                        print("Native player failed for both URLs, attempting FFmpeg for \(ch.uniformName)")
                                        self.player?.pause()
                                        self.player = nil
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            self.isUsingKSPlayer = true
                                            self.streamErrorMessage = nil
                                            self.isStreamLoading = false
                                        }
                                        return
                                    }

                                    self.isStreamLoading = false
                                    let isMKV = url.pathExtension.lowercased() == "mkv" || fallbackURL.pathExtension.lowercased() == "mkv" || url.absoluteString.contains(".mkv")
                                    if isMKV {
                                        self.streamErrorMessage = "MKV Format (Requires External Player)"
                                    } else {
                                        self.streamErrorMessage = "Stream unavailable from provider"
                                    }
                                }
                            }
                        }
                        player.replaceCurrentItem(with: fallbackItem)
                        player.play()
                    } else {
                        // No fallback URL; attempt FFmpeg if allowed
                        if let ch = self.activeDetailChannel ?? self.selectedChannel,
                           !self.isUsingKSPlayer,
                           self.playerEngine.enginePreference != .native {
                            print("Native player failed, switching to FFmpeg for \(ch.uniformName)")
                            self.player?.pause()
                            self.player = nil
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.isUsingKSPlayer = true
                                self.streamErrorMessage = nil
                                self.isStreamLoading = false
                            }
                            return
                        }

                        self.isStreamLoading = false
                        let isMKV = url.pathExtension.lowercased() == "mkv" || url.absoluteString.contains(".mkv")
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

        // Automatic stall-recovery
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak player] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                player?.play()
            }
        }

        // Playback failure tracking with fallback
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak player] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            print("AVPlayerItem error: \(error?.localizedDescription ?? "unknown") for \(url)")
            if let fallbackURL, fallbackURL != url {
                guard let player else { return }
                Task { @MainActor in
                    print("Retrying with fallback URL: \(fallbackURL)")
                    let fallbackAsset = AVURLAsset(url: fallbackURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                    let fallbackItem = AVPlayerItem(asset: fallbackAsset)
                    fallbackItem.preferredForwardBufferDuration = 4.0
                    fallbackItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                    fallbackItem.automaticallyPreservesTimeOffsetFromLive = true
                    player.replaceCurrentItem(with: fallbackItem)
                    player.play()
                }
            }
        }

        return player
    }

    private func stopPlayback() {
        videoValidationTask?.cancel()
        videoValidationTask = nil
        presentationSizeObserver?.invalidate()
        presentationSizeObserver = nil
        activeStatusObserver?.invalidate()
        activeStatusObserver = nil
        streamErrorMessage = nil
        isStreamLoading = false
        player?.pause()
        player = nil
        isUsingKSPlayer = false
        selectedChannelID = nil
        activeDetailChannel = nil
        isPresentingFullScreenPlayer = false
    }

    private func loadVODContent() async {
        guard !isLoadingVOD else { return }
        isLoadingVOD = true
        defer { isLoadingVOD = false }

        guard !playlistUsername.isEmpty && !playlistPassword.isEmpty else {
            let currentChannels = channels
            let (m, s) = await Task.detached(priority: .userInitiated) {
                let movies = currentChannels.filter { ch in
                    let path = ch.streamURL.path.lowercased()
                    let group = ch.group?.lowercased() ?? ""
                    return path.hasSuffix(".mp4") || path.hasSuffix(".mkv") || group.contains("vod") || (group.contains("movie") && !group.contains("live"))
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
                    guard group.contains("series") || group.contains("season") || group.contains("boxset") || ch.category == .series else {
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
            self.movies = m
            self.series = s
            return
        }

        // Fetch movies first and update UI immediately so user gets content right away
        let m = await XtreamService.fetchXtreamVOD(baseURL: playlistURL, username: playlistUsername, password: playlistPassword)
        self.movies = m

        // Then fetch series sequentially to prevent simultaneous RAM spikes
        let s = await XtreamService.fetchXtreamSeries(baseURL: playlistURL, username: playlistUsername, password: playlistPassword)
        self.series = s
    }

    private func loadPlaylist() async {
        guard let url = validatedPlaylistURL else {
            playlistMessage = "Enter a valid HTTP or HTTPS playlist URL."
            return
        }

        isLoadingPlaylist = true
        playlistMessage = nil

        do {
            // 1. Check if this is an Xtream Codes server (server URL + username + password)
            if !playlistUsername.isEmpty && !playlistPassword.isEmpty {
                let isXtream = await XtreamService.isXtreamServer(
                    baseURL: playlistURL,
                    username: playlistUsername,
                    password: playlistPassword
                )
                if isXtream {
                    let xtreamChannels = try await XtreamService.fetchXtreamChannels(
                        baseURL: playlistURL,
                        username: playlistUsername,
                        password: playlistPassword
                    )
                    channels = xtreamChannels
                    updateVisibleChannels()
                    selectedCategory = .all
                    playlistMessage = "\(xtreamChannels.count) channels loaded."
                    activeSheet = nil
                    isLoadingPlaylist = false
                    Task {
                        await loadVODContent()
                    }
                    return
                }
            }

            // 2. Standard M3U / M3U8 Playlist Stream Loader (Ultra-low RAM streaming via disk)
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            request.setValue(XtreamService.defaultUserAgent, forHTTPHeaderField: "User-Agent")

            if !playlistUsername.isEmpty || !playlistPassword.isEmpty {
                let credentialString = "\(playlistUsername):\(playlistPassword)"
                if let credentialData = credentialString.data(using: .utf8) {
                    let base64Credential = credentialData.base64EncodedString()
                    request.setValue("Basic \(base64Credential)", forHTTPHeaderField: "Authorization")
                }
            }

            let (tempFileURL, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: tempFileURL) }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlaylistError.unavailable
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw PlaylistError.unauthorized
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw PlaylistError.unavailable
            }

            let importedChannels = try await PlaylistParser.channels(fromFileURL: tempFileURL)
            guard !importedChannels.isEmpty else {
                throw PlaylistError.noChannels
            }

            channels = importedChannels
            updateVisibleChannels()
            selectedCategory = .all
            playlistMessage = "\(importedChannels.count) channels loaded."
            activeSheet = nil
        } catch {
            playlistMessage = error.localizedDescription
        }

        isLoadingPlaylist = false
    }

    private func deletePlaylist() {
        stopPlayback()
        playlistURL = ""
        playlistUsername = ""
        playlistPassword = ""
        channels = []
        updateVisibleChannels()
        movies = []
        series = []
        selectedChannelID = nil
        activeDetailChannel = nil
        selectedCategory = .all
        searchText = ""
        playlistMessage = nil
    }

    private var validatedPlaylistURL: URL? {
        guard let url = URL(string: playlistURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }
}

// MARK: - Custom Bottom Tab Bar

struct BottomTabBar: View {
    @Binding var selectedTab: AppTab
    let onSelectTab: (AppTab) -> Void

    var body: some View {
        HStack {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selectedTab
                Button {
                    Haptics.selection()
                    onSelectTab(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? tiptvTheme.accent : .white.opacity(0.42))

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? tiptvTheme.accent : .white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.black.opacity(0.7)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Channel Library View

struct ChannelLibraryView: View {
    let channels: [Channel]
    let totalChannelCount: Int
    let categories: [NetflixCategory]
    let categoryCounts: [NetflixCategory: Int]
    @Binding var selectedCategory: NetflixCategory
    @Binding var selectedChannelID: Channel.ID?
    @Binding var searchText: String
    let isLoading: Bool
    let onSelectChannel: (Channel) -> Void
    let openPlaylistImporter: () -> Void
    let reloadPlaylist: () -> Void
    let deletePlaylist: () -> Void

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var isShowingDeleteConfirmation = false
    @State private var displayLimit = 250

    private var paginatedChannels: [Channel] {
        if channels.count <= displayLimit {
            return channels
        }
        return Array(channels.prefix(displayLimit))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Floating Netflix-Style Category Filter Pills
            if categories.count > 1 {
                CategoryPillsBar(
                    categories: categories,
                    categoryCounts: categoryCounts,
                    selectedCategory: $selectedCategory
                )
                .padding(.vertical, 6)
            }

            List {
                Section {
                    if isLoading {
                        ForEach(0..<6, id: \.self) { _ in
                            LoadingChannelSkeletonRow()
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if channels.isEmpty {
                        if selectedCategory == .favorites {
                            NoFavoritesCard(browseAllChannels: { selectedCategory = .all })
                                .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else if totalChannelCount == 0 {
                            EmptyChannelListCard(openPlaylistImporter: openPlaylistImporter)
                                .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            NoSearchResultsCard(
                                searchText: searchText,
                                clearSearch: { searchText = "" }
                            )
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else {
                        ForEach(paginatedChannels) { channel in
                            Button {
                                onSelectChannel(channel)
                            } label: {
                                ChannelRow(
                                    channel: channel,
                                    isSelected: channel.id == selectedChannelID,
                                    isFavorite: favoritesManager.isFavorite(channel)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Haptics.medium()
                                    withAnimation {
                                        HiddenChannelsManager.shared.hideChannel(channel)
                                    }
                                } label: {
                                    Label("Hide", systemImage: "eye.slash.fill")
                                }

                                Button {
                                    Haptics.light()
                                    withAnimation {
                                        FavoritesManager.shared.toggleFavorite(channel)
                                    }
                                } label: {
                                    Label(
                                        favoritesManager.isFavorite(channel) ? "Unfavorite" : "Favorite",
                                        systemImage: favoritesManager.isFavorite(channel) ? "heart.slash.fill" : "heart.fill"
                                    )
                                }
                                .tint(favoritesManager.isFavorite(channel) ? .gray : tiptvTheme.liveRed)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Haptics.medium()
                                    withAnimation {
                                        HiddenChannelsManager.shared.hideChannel(channel)
                                    }
                                } label: {
                                    Label("Hide Channel", systemImage: "eye.slash")
                                }

                                Button {
                                    Haptics.light()
                                    withAnimation {
                                        FavoritesManager.shared.toggleFavorite(channel)
                                    }
                                } label: {
                                    Label(
                                        FavoritesManager.shared.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites",
                                        systemImage: FavoritesManager.shared.isFavorite(channel) ? "heart.slash" : "heart"
                                    )
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        if channels.count > displayLimit {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(tiptvTheme.accent)
                                    .padding(.vertical, 12)
                                    .onAppear {
                                        displayLimit = min(displayLimit + 250, channels.count)
                                    }
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    ChannelSectionHeader(
                        displayedCount: channels.count,
                        totalCount: totalChannelCount,
                        isFiltered: !searchText.isEmpty || selectedCategory != .all,
                        categoryTitle: selectedCategory.rawValue
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .navigationTitle("TV Guide")
        .searchable(text: $searchText, prompt: "Search channels")
        .onChange(of: selectedCategory) {
            displayLimit = 250
        }
        .onChange(of: searchText) {
            displayLimit = 250
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if totalChannelCount > 0 {
                    Menu {
                        Button(action: reloadPlaylist) {
                            Label("Reload Channels", systemImage: "arrow.clockwise")
                        }

                        Button(action: openPlaylistImporter) {
                            Label("Edit Playlist URL", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Playlist Options")
                }

                Button(action: openPlaylistImporter) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Add Playlist")
            }
        }
        .confirmationDialog(
            "Delete Playlist?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                deletePlaylist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the saved playlist URL and credentials, and clear all channels.")
        }
    }
}

// MARK: - Full Screen Video Player View

struct FullScreenPlayerView: View {
    let channel: Channel
    let allChannels: [Channel]
    let player: AVPlayer?
    var isUsingKSPlayer: Bool = false
    let onSelectChannel: (Channel) -> Void
    let onDismiss: () -> Void
    let onStop: () -> Void
    var onTogglePlayerEngine: (() -> Void)? = nil

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var pipManager = PiPManager.shared

    private var isFFmpegActive: Bool {
        isUsingKSPlayer || channel.streamURLString.lowercased().contains(".mkv")
    }

    @StateObject private var mkvCoordinator = KSVideoPlayer.Coordinator()

    @State private var areControlsVisible = true
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var isAspectFill = false
    @State private var controlsTimerTask: Task<Void, Never>?

    // VOD Playback Scrubber State
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var timeObserverToken: Any? = nil
    @State private var playbackRate: Float = 1.0

    // Audio / Subtitles & Sleep Timer
    @StateObject private var sleepTimerManager = SleepTimerManager()
    @State private var isAudioSubtitleSheetVisible = false

    private var isVODContent: Bool {
        let path = channel.streamURL.path.lowercased()
        let urlStr = channel.streamURL.absoluteString.lowercased()
        let isFileExt = path.hasSuffix(".mp4") || path.hasSuffix(".mkv") || path.hasSuffix(".avi") || path.hasSuffix(".m4v")
        let isVODPath = urlStr.contains("/movie/") || urlStr.contains("/series/")
        let hasFiniteDuration = (player?.currentItem?.duration.isValid == true && player?.currentItem?.duration.isIndefinite == false && (player?.currentItem?.duration.seconds ?? 0) > 0)
        return isFileExt || isVODPath || hasFiniteDuration
    }

    @State private var currentIndex: Int = -1

    private var hasPrevious: Bool {
        currentIndex > 0
    }

    private var hasNext: Bool {
        currentIndex >= 0 && currentIndex < allChannels.count - 1
    }

    private func updateCurrentIndex() {
        currentIndex = allChannels.firstIndex(where: { $0.id == channel.id }) ?? -1
    }

    private var isFavorite: Bool {
        favoritesManager.isFavorite(channel)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // Video Display (Fit or Fill with PiP Support)
                if isFFmpegActive {
                    MKVPlayerView(url: channel.streamURL, coordinator: mkvCoordinator, isAspectFill: isAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                } else if let player {
                    PiPVideoPlayer(player: player, isAspectFill: isAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }

                // Gesture & Tap Detection Overlay
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleAspectRatio()
                    }
                    .onTapGesture(count: 1) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            areControlsVisible.toggle()
                            if areControlsVisible {
                                resetControlsTimer()
                            } else {
                                controlsTimerTask?.cancel()
                            }
                        }
                    }

                // Playback Controls Overlay
                if areControlsVisible {
                    VStack(spacing: 0) {
                        topBar
                            .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()

                        centerControls
                            .transition(.scale(scale: 0.95).combined(with: .opacity))

                        Spacer()

                        bottomBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            if isFFmpegActive {
                isPlaying = true
                isMuted = mkvCoordinator.isMuted
                mkvCoordinator.isScaleAspectFill = isAspectFill
                mkvCoordinator.onPlay = { curTime, totalTime in
                    if !self.isScrubbing {
                        self.currentTime = curTime.isFinite ? max(0, curTime) : 0
                    }
                    if totalTime.isFinite && totalTime > 0 {
                        self.duration = totalTime
                    }
                }
                mkvCoordinator.onStateChanged = { layer, state in
                    if state == .paused {
                        self.isPlaying = false
                    } else if state == .buffering || state == .bufferFinished || state == .readyToPlay {
                        self.isPlaying = true
                    }
                }
            } else {
                isPlaying = player?.timeControlStatus != .paused
                isMuted = player?.isMuted ?? false
                if isVODContent {
                    setupTimeObserver()
                }
            }
            updateCurrentIndex()
            resetControlsTimer()
        }
        .onChange(of: channel.id) { _, _ in
            updateCurrentIndex()
            if isFFmpegActive {
                mkvCoordinator.resetPlayer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification)) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                player?.play()
            }
        }
        .onDisappear {
            if isFFmpegActive {
                mkvCoordinator.playerLayer?.pause()
                mkvCoordinator.resetPlayer()
            }
            removeTimeObserver()
            controlsTimerTask?.cancel()
            sleepTimerManager.cancel()
        }
        .sheet(isPresented: $isAudioSubtitleSheetVisible) {
            if isFFmpegActive {
                MKVAudioSubtitleSelectorSheet(coordinator: mkvCoordinator)
            } else if let player {
                AudioSubtitleSelectorSheet(player: player)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel("Back to Channels")

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.uniformName)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let group = channel.group {
                    Text(group)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Player Engine Toggle Badge
            if let onTogglePlayerEngine {
                Button {
                    Haptics.light()
                    if isFFmpegActive {
                        mkvCoordinator.playerLayer?.pause()
                        mkvCoordinator.resetPlayer()
                    }
                    onTogglePlayerEngine()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isFFmpegActive ? themeManager.accent : tiptvTheme.aqua)
                            .frame(width: 6, height: 6)
                        Text(isFFmpegActive ? "FFmpeg" : "Native")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
                }
                .accessibilityLabel("Toggle Player Engine (Currently \(isFFmpegActive ? "FFmpeg" : "Native"))")
            }

            // Picture-in-Picture Button
            if isFFmpegActive || pipManager.isSupported {
                Button {
                    Haptics.medium()
                    if isFFmpegActive {
                        mkvCoordinator.playerLayer?.isPipActive.toggle()
                    } else {
                        pipManager.togglePiP()
                    }
                } label: {
                    let isPiPActive = isFFmpegActive ? (mkvCoordinator.playerLayer?.isPipActive == true) : pipManager.isPiPActive
                    Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isPiPActive ? themeManager.accent : .white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel((isFFmpegActive ? (mkvCoordinator.playerLayer?.isPipActive == true) : pipManager.isPiPActive) ? "Exit Picture in Picture" : "Enter Picture in Picture")
            }

            // Sleep Timer
            Menu {
                Section("Sleep Timer") {
                    Button("Off") {
                        sleepTimerManager.cancel()
                    }
                    Button("15 Minutes") {
                        sleepTimerManager.setTimer(minutes: 15) { onStop() }
                    }
                    Button("30 Minutes") {
                        sleepTimerManager.setTimer(minutes: 30) { onStop() }
                    }
                    Button("45 Minutes") {
                        sleepTimerManager.setTimer(minutes: 45) { onStop() }
                    }
                    Button("60 Minutes") {
                        sleepTimerManager.setTimer(minutes: 60) { onStop() }
                    }
                    Button("90 Minutes") {
                        sleepTimerManager.setTimer(minutes: 90) { onStop() }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sleepTimerManager.isTimerActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 13, weight: .semibold))
                    if sleepTimerManager.isTimerActive {
                        Text(sleepTimerManager.formattedRemaining)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(sleepTimerManager.isTimerActive ? themeManager.accent : .white.opacity(0.85))
                .padding(.horizontal, sleepTimerManager.isTimerActive ? 8 : 0)
                .frame(height: 34)
                .frame(minWidth: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(sleepTimerManager.isTimerActive ? themeManager.accent.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 0.5)
                )
            }
            .accessibilityLabel("Sleep Timer")

            // Audio & Subtitles
            Button {
                Haptics.light()
                isAudioSubtitleSheetVisible = true
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel("Audio and Subtitles")

            // Favorite Button
            Button {
                Haptics.medium()
                favoritesManager.toggleFavorite(channel)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isFavorite ? tiptvTheme.liveRed : .white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")

            Button {
                if isFFmpegActive {
                    mkvCoordinator.playerLayer?.pause()
                    mkvCoordinator.resetPlayer()
                }
                onStop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel("Stop Playback")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var centerControls: some View {
        HStack(spacing: 30) {
            if isVODContent {
                // Infuse 10s Skip Backward
                Button {
                    skip(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel("Skip backward 10 seconds")
            } else {
                Button(action: playPreviousChannel) {
                    Image(systemName: "backward.end")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(hasPrevious ? .white.opacity(0.85) : .white.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(hasPrevious ? 0.18 : 0.06), lineWidth: 0.5)
                        )
                }
                .disabled(!hasPrevious)
                .accessibilityLabel("Previous Channel")
            }

            Button(action: togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: themeManager.accent.opacity(0.35), radius: 14, y: 3)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 1.5)
                }
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            if isVODContent {
                // Infuse 10s Skip Forward
                Button {
                    skip(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel("Skip forward 10 seconds")
            } else {
                Button(action: playNextChannel) {
                    Image(systemName: "forward.end")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(hasNext ? .white.opacity(0.85) : .white.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(hasNext ? 0.18 : 0.06), lineWidth: 0.5)
                        )
                }
                .disabled(!hasNext)
                .accessibilityLabel("Next Channel")
            }
        }
    }

    private var vodScrubberBar: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let effectiveDuration = duration > 0 ? duration : 1.0
                let progress = duration > 0 ? (isScrubbing ? scrubTime : currentTime) / effectiveDuration : 0
                let clampedProgress = min(max(progress, 0.0), 1.0)
                let barWidth = geo.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: isScrubbing ? 6 : 4)

                    Capsule()
                        .fill(themeManager.accent)
                        .frame(width: max(0, barWidth * CGFloat(clampedProgress)), height: isScrubbing ? 6 : 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                        .shadow(color: themeManager.accent.opacity(0.6), radius: 6, y: 1)
                        .offset(x: max(0, min(barWidth * CGFloat(clampedProgress) - (isScrubbing ? 8 : 5), max(0, barWidth - (isScrubbing ? 16 : 10)))))
                }
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isScrubbing {
                                isScrubbing = true
                                resetControlsTimer()
                            }
                            let touchX = max(0, min(value.location.x, barWidth))
                            let ratio = barWidth > 0 ? touchX / barWidth : 0
                            scrubTime = Double(ratio) * duration
                        }
                        .onEnded { value in
                            let touchX = max(0, min(value.location.x, barWidth))
                            let ratio = barWidth > 0 ? touchX / barWidth : 0
                            let targetTime = Double(ratio) * duration
                            seek(to: targetTime)
                            currentTime = targetTime
                            isScrubbing = false
                            resetControlsTimer()
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTime(isScrubbing ? scrubTime : currentTime))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                if duration > 0 {
                    let remaining = max(0, duration - (isScrubbing ? scrubTime : currentTime))
                    Text("-\(formatTime(remaining))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if isVODContent {
                vodScrubberBar
            }

            HStack(spacing: 10) {
                // Stream Type Badge (VOD or LIVE) moved to bottom to prevent top bar clipping
                HStack(spacing: 5) {
                    Circle()
                        .fill(isVODContent ? themeManager.accent : tiptvTheme.liveRed)
                        .frame(width: 5, height: 5)

                    Text(isVODContent ? "VOD" : "LIVE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            if currentIndex >= 0 {
                Text("\(currentIndex + 1) of \(allChannels.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }

            Spacer()

            if isVODContent {
                Menu {
                    Section("Playback Speed") {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button {
                                Haptics.selection()
                                playbackRate = Float(speed)
                                if isFFmpegActive {
                                    mkvCoordinator.playbackRate = Float(speed)
                                } else {
                                    player?.rate = Float(speed)
                                }
                            } label: {
                                HStack {
                                    Text(speed == 1.0 ? "1.0x (Normal)" : String(format: "%.2gx", speed))
                                    if playbackRate == Float(speed) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 11, weight: .medium))
                        Text(playbackRate == 1.0 ? "1.0x" : String(format: "%.2gx", playbackRate))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(playbackRate != 1.0 ? themeManager.accent : .white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(playbackRate != 1.0 ? themeManager.accent.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .accessibilityLabel("Playback Speed")
            }

            Button(action: toggleAspectRatio) {
                HStack(spacing: 5) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 12, weight: .medium))
                    Text(isAspectFill ? "Fill" : "Fit")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(isAspectFill ? themeManager.accent : .white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isAspectFill ? themeManager.accent.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            .accessibilityLabel(isAspectFill ? "Switch to Fit" : "Switch to Fill")

            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMuted ? .white.opacity(0.5) : .white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel(isMuted ? "Unmute Audio" : "Mute Audio")
        }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.4), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func togglePlayPause() {
        if isFFmpegActive {
            if isPlaying {
                mkvCoordinator.playerLayer?.pause()
                isPlaying = false
            } else {
                mkvCoordinator.playerLayer?.play()
                isPlaying = true
            }
        } else {
            if isPlaying {
                player?.pause()
                isPlaying = false
            } else {
                player?.play()
                isPlaying = true
            }
        }
        resetControlsTimer()
    }

    private func toggleMute() {
        if isFFmpegActive {
            isMuted.toggle()
            mkvCoordinator.isMuted = isMuted
        } else {
            guard let player else { return }
            player.isMuted.toggle()
            isMuted = player.isMuted
        }
        resetControlsTimer()
    }

    private func toggleAspectRatio() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAspectFill.toggle()
            if isFFmpegActive {
                mkvCoordinator.isScaleAspectFill = isAspectFill
            }
        }
        resetControlsTimer()
    }

    private func playPreviousChannel() {
        guard hasPrevious, currentIndex - 1 >= 0 else { return }
        Haptics.medium()
        onSelectChannel(allChannels[currentIndex - 1])
        resetControlsTimer()
    }

    private func playNextChannel() {
        guard hasNext, currentIndex + 1 < allChannels.count else { return }
        Haptics.medium()
        onSelectChannel(allChannels[currentIndex + 1])
        resetControlsTimer()
    }

    private func setupTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player else { return }
            if !self.isScrubbing {
                self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
            }
            if let itemDuration = player.currentItem?.duration, itemDuration.isValid && !itemDuration.isIndefinite {
                let sec = itemDuration.seconds
                if sec.isFinite && sec > 0 {
                    self.duration = sec
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func seek(to seconds: Double) {
        if isFFmpegActive {
            mkvCoordinator.seek(time: max(0, min(seconds, duration)))
        } else {
            guard let player else { return }
            let targetCMTime = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
            player.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func skip(seconds: Double) {
        Haptics.light()
        let target = max(0, min(currentTime + seconds, duration))
        seek(to: target)
        currentTime = target
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    private func resetControlsTimer() {
        controlsTimerTask?.cancel()
        controlsTimerTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        areControlsVisible = false
                    }
                }
            }
        }
    }
}

// MARK: - Mini Player Bar

struct MiniPlayerBar: View {
    let channel: Channel
    let player: AVPlayer?
    var isUsingKSPlayer: Bool = false
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isPlaying = true

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        if let player, !isUsingKSPlayer {
                            VideoPlayer(player: player)
                                .disabled(true)
                                .aspectRatio(16 / 9, contentMode: .fill)
                                .frame(width: 72, height: 44)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            ChannelArtwork(
                                logoURL: channel.logoURL,
                                channelName: channel.uniformName,
                                size: 44,
                                cornerRadius: 8
                            )
                        }

                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .frame(width: 72, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.uniformName)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(isUsingKSPlayer ? tiptvTheme.accent : tiptvTheme.aqua)
                                .frame(width: 4, height: 4)

                            Text(channel.group ?? "Live TV")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button {
                if let player, !isUsingKSPlayer {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    } else {
                        player.play()
                        isPlaying = true
                    }
                } else {
                    onTap()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Playback")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tiptvTheme.accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: tiptvTheme.accent.opacity(0.2), radius: 10, y: 3)
        )
    }
}

// MARK: - Netflix-Style Category Pills Bar

struct CategoryPillsBar: View {
    let categories: [NetflixCategory]
    let categoryCounts: [NetflixCategory: Int]
    @Binding var selectedCategory: NetflixCategory
    @Namespace private var pillNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { category in
                        let isSelected = category == selectedCategory
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                selectedCategory = category
                                proxy.scrollTo(category.id, anchor: .center)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(category == .favorites ? tiptvTheme.liveRed : (isSelected ? .white : .white.opacity(0.65)))

                                Text(category.rawValue)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.68))

                                if let count = categoryCounts[category] {
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: isSelected ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white.opacity(0.95) : .white.opacity(0.4))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            isSelected
                                                ? Color.white.opacity(0.2)
                                                : Color.white.opacity(0.06),
                                            in: Capsule()
                                        )
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(category == .favorites ? AnyShapeStyle(Color.red.opacity(0.6)) : AnyShapeStyle(tiptvTheme.artworkGradient))
                                        .matchedGeometryEffect(id: "activeCategoryPill", in: pillNamespace)
                                        .shadow(color: (category == .favorites ? Color.red : tiptvTheme.accent).opacity(0.38), radius: 8, y: 2)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(category.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    proxy.scrollTo(newCategory.id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Section Header

struct ChannelSectionHeader: View {
    let displayedCount: Int
    let totalCount: Int
    let isFiltered: Bool
    var categoryTitle: String = "All Channels"

    var body: some View {
        HStack(alignment: .center) {
            Text(isFiltered ? categoryTitle.uppercased() : "ALL CHANNELS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.38))

            Spacer()

            Text("\(displayedCount) \(displayedCount == 1 ? "channel" : "channels")")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06), in: Capsule())
                .foregroundStyle(.white.opacity(0.5))
        }
        .textCase(nil)
        .padding(.top, 4)
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: Channel
    let isSelected: Bool
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ChannelArtwork(
                logoURL: channel.logoURL,
                channelName: channel.uniformName,
                size: 50,
                cornerRadius: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.uniformName)
                        .lineLimit(1)
                        .font(.system(.body, design: .rounded).weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.white)

                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(tiptvTheme.liveRed)
                    }
                }

                if isSelected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tiptvTheme.aqua)
                            .frame(width: 4, height: 4)

                        Text("Playing")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(tiptvTheme.aqua)
                    }
                } else if let group = channel.group, !group.isEmpty {
                    Text(group)
                        .lineLimit(1)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("Live TV")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tiptvTheme.aqua)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? tiptvTheme.accent.opacity(0.2) : tiptvTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSelected ? tiptvTheme.accent.opacity(0.6) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: isSelected ? tiptvTheme.accent.opacity(0.25) : .clear,
                    radius: 8,
                    y: 3
                )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isSelected ? "Currently playing" : "Plays this channel")
    }
}

// MARK: - In-Memory & Network Artwork Cache

final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager()

    private let cache = NSCache<NSURL, UIImage>()
    private let failedURLs = NSCache<NSURL, NSNumber>()
    private let session: URLSession

    private init() {
        cache.countLimit = 1000
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB RAM limit
        failedURLs.countLimit = 5000

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.httpMaximumConnectionsPerHost = 3
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func isFailed(url: URL) -> Bool {
        failedURLs.object(forKey: url as NSURL) != nil
    }

    func setImage(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = image(for: url) {
            return cached
        }
        if isFailed(url: url) {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(XtreamService.defaultUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let uiImage = downsample(data: data, to: 300) ?? UIImage(data: data) else {
                failedURLs.setObject(NSNumber(value: true), forKey: url as NSURL)
                return nil
            }
            setImage(uiImage, for: url)
            return uiImage
        } catch {
            failedURLs.setObject(NSNumber(value: true), forKey: url as NSURL)
            return nil
        }
    }

    private func downsample(data: Data, to maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Channel Artwork

struct ChannelArtwork: View {
    let logoURL: URL?
    let channelName: String
    var size: CGFloat = 50
    var cornerRadius: CGFloat? = nil

    @State private var uiImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    private var effectiveRadius: CGFloat {
        cornerRadius ?? (size * 0.26)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: effectiveRadius)
                .fill(Color.white.opacity(0.06))

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: effectiveRadius))
        .overlay {
            RoundedRectangle(cornerRadius: effectiveRadius)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: logoURL) { _, _ in
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadImage() {
        guard let logoURL else {
            uiImage = nil
            return
        }

        if let cached = ImageCacheManager.shared.image(for: logoURL) {
            uiImage = cached
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            let loaded = await ImageCacheManager.shared.loadImage(from: logoURL)
            guard !Task.isCancelled else { return }
            if let loaded {
                self.uiImage = loaded
            }
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            tiptvTheme.artworkGradient

            Text(channelInitial)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var channelInitial: String {
        let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "TV"
    }
}

// MARK: - Loading & Empty States

struct LoadingChannelSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 14)
                    .frame(maxWidth: 160)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 10)
                    .frame(maxWidth: 90)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tiptvTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

struct NoFavoritesCard: View {
    let browseAllChannels: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tiptvTheme.liveRed.opacity(0.18))
                    .frame(width: 56, height: 56)

                Image(systemName: "heart.slash")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(tiptvTheme.liveRed)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("No Favorites Added")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)

                Text("Tap the heart icon on any channel or player to add it to your favorites.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button("Browse All Channels", action: browseAllChannels)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(tiptvTheme.artworkGradient, in: Capsule())
                .buttonStyle(.plain)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tiptvTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

struct EmptyChannelListCard: View {
    let openPlaylistImporter: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: tiptvTheme.accent.opacity(0.35), radius: 10, y: 3)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("No Channels Added")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)

                Text("Add an M3U or M3U8 playlist URL to start streaming live TV.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button(action: openPlaylistImporter) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add Playlist")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(tiptvTheme.artworkGradient, in: Capsule())
                .shadow(color: tiptvTheme.accent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tiptvTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

struct NoSearchResultsCard: View {
    let searchText: String
    let clearSearch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(tiptvTheme.aqua.opacity(0.8))
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("No Matching Channels")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)

                Text("No channels match “\(searchText)”. Try checking the spelling or picking a different category.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button("Clear Search", action: clearSearch)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(tiptvTheme.aqua)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(tiptvTheme.aqua.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tiptvTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Playlist Importer

struct PlaylistImportView: View {
    @Binding var playlistURL: String
    @Binding var username: String
    @Binding var password: String
    let isLoading: Bool
    let message: String?
    let loadPlaylist: () async -> Void
    let deletePlaylist: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist URL") {
                    TextField("https://example.com/playlist.m3u", text: $playlistURL)
                        .disableAutocapitalization()
                        .autocorrectionDisabled()
                        .urlKeyboard()
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        TextField("Username (Optional)", text: $username)
                            .disableAutocapitalization()
                            .autocorrectionDisabled()
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        if isShowingPassword {
                            TextField("Password (Optional)", text: $password)
                                .disableAutocapitalization()
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Password (Optional)", text: $password)
                        }

                        Button {
                            isShowingPassword.toggle()
                        } label: {
                            Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
                    }
                } header: {
                    Text("Authentication (Optional)")
                } footer: {
                    Text("Provide username and password if your IPTV provider requires authentication.")
                }

                Section {
                    Text("Use a playlist you are authorized to access. tiptv supports standard M3U, M3U8, and Xtream Codes playlists.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if !playlistURL.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(playlistURL.isEmpty ? "Add Playlist" : "Manage Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") {
                        Task {
                            await loadPlaylist()
                        }
                    }
                    .disabled(playlistURL.isEmpty || isLoading)
                }
            }
            .confirmationDialog(
                "Delete Playlist?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    deletePlaylist()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the saved playlist URL and credentials, and clear all channels.")
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading playlist…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .tint(tiptvTheme.accent)
        }
    }
}

// MARK: - Models & Helpers

struct Channel: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let uniformName: String
    let group: String?
    let logoURL: URL?
    let streamURL: URL
    let streamURLString: String
    let category: NetflixCategory
    let searchKey: String

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        uniformName: String? = nil,
        group: String? = nil,
        logoURL: URL? = nil,
        streamURL: URL,
        streamURLString: String? = nil,
        category: NetflixCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.streamURL = streamURL
        let resolvedURLString = streamURLString ?? streamURL.absoluteString
        self.streamURLString = resolvedURLString
        let resolvedUniformName = uniformName ?? PlaylistParser.uniformChannelName(name)
        self.uniformName = resolvedUniformName
        self.category = category ?? NetflixCategory.classify(group: group, name: name)
        self.searchKey = "\(name) \(resolvedUniformName) \(group ?? "")".lowercased()
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }

    var isMovie: Bool {
        if category == .movies { return true }
        let lowerURL = streamURLString.lowercased()
        if lowerURL.contains("/movie/") || lowerURL.contains("/movies/") || lowerURL.contains("/vod/") || lowerURL.contains("/vods/") {
            return true
        }
        if lowerURL.contains("/series/") { return false }
        let groupLower = group?.lowercased() ?? ""
        if groupLower.contains("series") || groupLower.contains("season") || groupLower.contains("boxset") || groupLower.contains("episodes") {
            return false
        }
        let nameLower = name.lowercased()
        if nameLower.contains("s01") || nameLower.contains("s02") || nameLower.contains("s03") || nameLower.contains("e01") || nameLower.contains("e02") {
            return false
        }

        // Group-based detection for movie categories
        let movieGroupKeywords = [
            "movie", "vod", "cinema", "film", "films", "kino", "pelicula", "filme",
            "action", "comedy", "thriller", "horror", "drama", "sci-fi",
            "romance", "adventure", "crime", "family", "animation",
            "western", "war", "fantasy", "mystery", "hollywood", "box office",
            "disney", "netflix", "prime", "amazon", "apple tv", "hbo", "paramount",
            "starz", "cinemax", "showtime", "bluray", "web-dl", "remux", "4k uhd",
            "new releases", "top picks", "trending"
        ]
        if movieGroupKeywords.contains(where: { groupLower.contains($0) }) && !groupLower.contains("live") && !groupLower.contains("sport") && !groupLower.contains("news") {
            return true
        }

        // File extension detection anywhere in URL (handles query parameters as well)
        let fileExtensions = [".mp4", ".mkv", ".avi", ".m4v", ".mov", ".webm", ".wmv", ".flv"]
        let hasVODExtension = fileExtensions.contains(where: { lowerURL.contains($0) })
        if hasVODExtension && !groupLower.contains("live") && !groupLower.contains("channel") && !groupLower.contains("sport") && !groupLower.contains("news") {
            return true
        }

        // 4-digit release year in name, e.g. "Oppenheimer (2023)" or "Barbie [2023]"
        if let regex = try? NSRegularExpression(pattern: #"[\(\[]\s*(19\d{2}|20\d{2})\s*[\)\]]"#) {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                if !groupLower.contains("live") && !groupLower.contains("sport") && !groupLower.contains("news") && !groupLower.contains("channel") {
                    return true
                }
            }
        }

        return false
    }

    var isSeries: Bool {
        if category == .series { return true }
        let lowerURL = streamURLString.lowercased()
        if lowerURL.contains("/series/") { return true }
        let groupLower = group?.lowercased() ?? ""
        if groupLower.contains("series") || groupLower.contains("season") || groupLower.contains("boxset") || groupLower.contains("tv shows") || groupLower.contains("tv series") {
            return true
        }
        let nameLower = name.lowercased()
        if nameLower.contains("s01") || nameLower.contains("s02") || nameLower.contains("s03") || nameLower.contains("e01") || nameLower.contains("e02") || nameLower.contains("season ") || nameLower.contains("episode ") {
            return true
        }
        if let regex = try? NSRegularExpression(pattern: #"\b[sS]\d{1,2}\s*[eE]\d{1,2}\b"#) {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                return true
            }
        }
        return false
    }

    var isVOD: Bool {
        isMovie || isSeries
    }
}

enum PlaylistError: LocalizedError {
    case unavailable
    case noChannels
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The playlist could not be downloaded. Check the URL and credentials."
        case .noChannels:
            return "No playable channels were found in this playlist."
        case .unauthorized:
            return "Authentication failed (401/403). Please verify your username and password."
        }
    }
}

enum PlaylistParser {
    // Static pre-compiled regular expressions for fast linear-time matching
    nonisolated private static let prefixRegexes: [NSRegularExpression] = [
        #"^[A-Za-z]{2,4}\s*[:|\-•/]\s*"#,
        #"^\[[A-Za-z]{2,4}\]\s*"#,
        #"^\|[A-Za-z]{2,4}\|\s*"#,
        #"^(VIP|HD|FHD|4K|RAW)\s*[:|\-•/]\s*"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    nonisolated private static let suffixRegexes: [NSRegularExpression] = [
        #"\s*\((BACKUP|BACK-UP|BACK UP|1080P|720P|50FPS|60FPS|25FPS|HEVC|H265|H\.265|RAW|LOW)\)"#,
        #"\s*\[(BACKUP|BACK-UP|BACK UP|1080P|720P|50FPS|60FPS|25FPS|HEVC|H265|H\.265|RAW|LOW)\]"#,
        #"\s+\b(50FPS|60FPS|25FPS|RAW)\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    nonisolated private static let acronyms: Set<String> = [
        "UK", "US", "USA", "GB", "CA", "AU", "NZ", "IE", "FR", "DE", "ES", "IT", "NL",
        "HD", "FHD", "UHD", "4K", "8K", "SD", "HEVC", "H265", "RAW",
        "TV", "VIP", "PPV", "VOD", "EPG",
        "BBC", "ITV", "CNN", "HBO", "SKY", "TNT", "ESPN", "NBC", "CBS", "ABC", "FOX", "MTV",
        "BT", "MLB", "NBA", "NFL", "NHL", "UFC", "WWE", "F1", "FIA"
    ]

    /// Streams directly from a downloaded file on disk using memory-mapping on a background thread
    nonisolated static func channels(fromFileURL fileURL: URL) async throws -> [Channel] {
        return try await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                throw PlaylistError.unavailable
            }
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw PlaylistError.unavailable
            }
            return channels(from: content)
        }.value
    }

    /// Fast line-by-line enumerator without intermediate array allocation
    nonisolated static func channels(from playlist: String) -> [Channel] {
        var channels: [Channel] = []
        channels.reserveCapacity(min(playlist.count / 80, 50000))
        var name = ""
        var group: String?
        var logoURL: URL?

        playlist.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }

            if line.hasPrefix("#EXTINF:") {
                name = line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "Untitled Channel"
                group = attribute(named: "group-title", in: line)
                logoURL = attribute(named: "tvg-logo", in: line).flatMap(URL.init(string:))
            } else if !line.hasPrefix("#"), let streamURL = URL(string: line) {
                let rawName = name.isEmpty ? (streamURL.host ?? "Untitled Channel") : name
                let cleanedName = cleanSeparators(rawName)
                let cleanedGroup = group.map(cleanSeparators)
                let uniform = uniformChannelName(cleanedName)
                let cat = NetflixCategory.classify(group: cleanedGroup, name: cleanedName)

                channels.append(
                    Channel(
                        id: UUID(),
                        name: cleanedName,
                        uniformName: uniform,
                        group: cleanedGroup,
                        logoURL: logoURL,
                        streamURL: streamURL,
                        streamURLString: line,
                        category: cat
                    )
                )
                name = ""
                group = nil
                logoURL = nil
            }
        }

        return channels
    }

    nonisolated static func uniformChannelName(_ raw: String) -> String {
        var text = cleanSeparators(raw)

        for regex in prefixRegexes {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        for regex in suffixRegexes {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        text = text.replacingOccurrences(of: "|", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ":|-•/ "))

        if !text.isEmpty {
            text = formatComponent(text)
        }

        return text.isEmpty ? raw : text
    }

    nonisolated static func cleanSeparators(_ text: String) -> String {
        guard text.contains(";") else { return text }

        let parts = text
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return text }

        return parts
            .map { formatComponent($0) }
            .joined(separator: " • ")
    }

    nonisolated private static func formatComponent(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespaces)
        let formattedWords = words.map { word -> String in
            let upper = word.uppercased()

            if acronyms.contains(upper) {
                return upper
            }

            if word.count > 2 && word == upper && word.rangeOfCharacter(from: .letters) != nil {
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }

            return word
        }
        return formattedWords.joined(separator: " ")
    }

    nonisolated private static func attribute(named name: String, in line: String) -> String? {
        let doubleQuoteTarget = name + "=\""
        if let startRange = line.range(of: doubleQuoteTarget) {
            let remainder = line[startRange.upperBound...]
            if let quoteRange = remainder.firstIndex(of: "\"") {
                return String(remainder[..<quoteRange])
            }
        }
        let singleQuoteTarget = name + "='"
        if let startRange = line.range(of: singleQuoteTarget) {
            let remainder = line[startRange.upperBound...]
            if let quoteRange = remainder.firstIndex(of: "'") {
                return String(remainder[..<quoteRange])
            }
        }
        return nil
    }
}

#Preview {
    ContentView()
}

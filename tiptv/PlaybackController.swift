import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackController {
    private(set) var player: AVPlayer?
    private(set) var playingChannel: Channel?
    private(set) var isUsingKSPlayer = false
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    @ObservationIgnored private var videoValidationTask: Task<Void, Never>?
    @ObservationIgnored private var presentationSizeObserver: NSKeyValueObservation?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var stallObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private let engine = PlayerEngineManager.shared

    func prepare(_ channel: Channel) {
        cleanupObservers()
        player?.pause()
        player = nil
        playingChannel = channel
        errorMessage = nil
        isLoading = true
    }

    func useFFmpeg() {
        cleanupObservers()
        player?.pause()
        player = nil
        errorMessage = nil
        isLoading = false
        isUsingKSPlayer = true
    }

    func deferVODPlayback() {
        cleanupObservers()
        player?.pause()
        player = nil
        errorMessage = nil
        isLoading = false
        isUsingKSPlayer = false
    }

    func start(_ channel: Channel) {
        cleanupObservers()
        player?.pause()
        player = nil
        playingChannel = channel
        isUsingKSPlayer = false
        errorMessage = nil
        isLoading = true
        let fallbackURL = Self.fallbackURL(for: channel.streamURL)
        let newPlayer = makePlayer(for: channel.streamURL, fallbackURL: fallbackURL, channel: channel)
        player = newPlayer
        newPlayer.play()
    }

    func toggleEngine(for channel: Channel) {
        videoValidationTask?.cancel()
        let useFFmpeg = engine.toggleEngine(for: channel, currentIsFFmpeg: isUsingKSPlayer)
        useFFmpeg ? self.useFFmpeg() : start(channel)
    }

    func stop() {
        cleanupObservers()
        player?.pause()
        player = nil
        playingChannel = nil
        isUsingKSPlayer = false
        errorMessage = nil
        isLoading = false
        IdleTimerManager.setDisabled(false)
    }

    private func makePlayer(for url: URL, fallbackURL: URL?, channel: Channel) -> AVPlayer {
        let headers = ["User-Agent": XtreamService.defaultUserAgent]
        let item = makeItem(url: url, headers: headers)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [unowned self] item, _ in
            Task { @MainActor in
                guard let player = self.player, self.playingChannel?.id == channel.id else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.errorMessage = nil
                    player.play()
                    self.verifyVideoPlayback(for: item, channel: channel)
                case .failed:
                    if let fallbackURL, fallbackURL != url {
                        self.installFallback(fallbackURL, originalURL: url, headers: headers, player: player, channel: channel)
                    } else {
                        self.handleNativeFailure(for: channel, url: url)
                    }
                default:
                    break
                }
            }
        }

        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [unowned self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.player?.play()
            }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [unowned self] _ in
            Task { @MainActor in
                guard let player = self.player else { return }
                if let fallbackURL, fallbackURL != url {
                    self.installFallback(fallbackURL, originalURL: url, headers: headers, player: player, channel: channel)
                } else {
                    self.handleNativeFailure(for: channel, url: url)
                }
            }
        }
        return player
    }

    private func installFallback(
        _ fallbackURL: URL,
        originalURL: URL,
        headers: [String: String],
        player: AVPlayer,
        channel: Channel
    ) {
        let item = makeItem(url: fallbackURL, headers: headers)
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [unowned self] item, _ in
            Task { @MainActor in
                guard let player = self.player, self.playingChannel?.id == channel.id else { return }
                if item.status == .readyToPlay {
                    self.isLoading = false
                    self.errorMessage = nil
                    player.play()
                    self.verifyVideoPlayback(for: item, channel: channel)
                } else if item.status == .failed {
                    self.handleNativeFailure(for: channel, url: originalURL)
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handleNativeFailure(for channel: Channel, url: URL) {
        guard !isUsingKSPlayer, engine.enginePreference != .native else {
            isLoading = false
            errorMessage = url.pathExtension.caseInsensitiveCompare("mkv") == .orderedSame
                ? "MKV Format (Requires External Player)"
                : "Stream unavailable or unsupported format"
            return
        }
        useFFmpeg()
    }

    private func verifyVideoPlayback(for item: AVPlayerItem, channel: Channel) {
        videoValidationTask?.cancel()
        presentationSizeObserver?.invalidate()
        guard item.presentationSize.width <= 0 || item.presentationSize.height <= 0 else { return }

        presentationSizeObserver = item.observe(\.presentationSize, options: [.new]) { [unowned self] item, _ in
            guard item.presentationSize.width > 0, item.presentationSize.height > 0 else { return }
            Task { @MainActor in
                self.videoValidationTask?.cancel()
                self.presentationSizeObserver?.invalidate()
                self.presentationSizeObserver = nil
            }
        }

        let lowerURL = channel.streamURLString.lowercased()
        guard engine.enginePreference == .auto,
              lowerURL.contains(".ts") || lowerURL.contains("/live/") else { return }

        videoValidationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(4_500))
            guard let self, !Task.isCancelled,
                  self.player?.currentItem === item,
                  !self.isUsingKSPlayer else { return }
            let isPlaying = self.player?.timeControlStatus == .playing || (self.player?.rate ?? 0) > 0
            if isPlaying && (item.presentationSize.width <= 0 || item.presentationSize.height <= 0) {
                self.engine.markChannelRequiresFFmpeg(channel)
                self.useFFmpeg()
            }
        }
    }

    private func cleanupObservers() {
        videoValidationTask?.cancel()
        videoValidationTask = nil
        presentationSizeObserver?.invalidate()
        presentationSizeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        stallObserver = nil
        failureObserver = nil
    }

    private func makeItem(url: URL, headers: [String: String]) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.automaticallyPreservesTimeOffsetFromLive = true
        return item
    }

    private static func fallbackURL(for url: URL) -> URL? {
        let original = url.absoluteString
        let lower = original.lowercased()
        if lower.contains("/live/") {
            if lower.hasSuffix(".ts") || lower.contains(".ts?") {
                return URL(string: original.replacingOccurrences(of: ".ts", with: ".m3u8"))
            }
            if lower.hasSuffix(".m3u8") || lower.contains(".m3u8?") {
                return URL(string: original.replacingOccurrences(of: ".m3u8", with: ".ts"))
            }
        }
        if lower.contains("/movie/") || lower.contains("/series/") {
            if lower.hasSuffix(".mkv") { return URL(string: original.replacingOccurrences(of: ".mkv", with: ".mp4")) }
            if lower.hasSuffix(".mp4") { return URL(string: original.replacingOccurrences(of: ".mp4", with: ".mkv")) }
        }
        return nil
    }
}

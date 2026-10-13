import AVFoundation
import AVKit
import KSPlayer
import SwiftUI

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

  @State private var favoritesManager = FavoritesManager.shared
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
  @State private var timeObserverPlayer: AVPlayer?
  @State private var playbackRate: Float = 1.0

  // Audio / Subtitles & Sleep Timer
  @StateObject private var sleepTimerManager = SleepTimerManager()
  @State private var isAudioSubtitleSheetVisible = false

  private var isVODContent: Bool {
    let path = channel.streamURL.path.lowercased()
    let urlStr = channel.streamURL.absoluteString.lowercased()
    let isFileExt =
      path.hasSuffix(".mp4") || path.hasSuffix(".mkv") || path.hasSuffix(".avi")
      || path.hasSuffix(".m4v")
    let isVODPath = urlStr.contains("/movie/") || urlStr.contains("/series/")
    let hasFiniteDuration =
      (player?.currentItem?.duration.isValid == true
        && player?.currentItem?.duration.isIndefinite == false
        && (player?.currentItem?.duration.seconds ?? 0) > 0)
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
          MKVPlayerView(
            url: channel.streamURL, coordinator: mkvCoordinator, isAspectFill: isAspectFill
          )
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
        removeTimeObserver()
        mkvCoordinator.resetPlayer()
      }
    }
    .onChange(of: player?.currentItem) { _, _ in
      if !isFFmpegActive && isVODContent {
        setupTimeObserver()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification))
    { notification in
      guard notification.object as? AVPlayerItem === player?.currentItem else { return }
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
      mkvCoordinator.onPlay = nil
      mkvCoordinator.onStateChanged = nil
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
              .fill(isFFmpegActive ? themeManager.accent : TipTVTheme.aqua)
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
        .accessibilityLabel(
          "Toggle Player Engine (Currently \(isFFmpegActive ? "FFmpeg" : "Native"))")
      }

      // AirPlay is available for the native AVPlayer engine.
      if !isFFmpegActive, player != nil {
        AirPlayRoutePicker()
          .frame(width: 34, height: 34)
          .background(.ultraThinMaterial, in: Circle())
          .overlay(
            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
          )
          .accessibilityLabel("AirPlay")
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
          let isPiPActive =
            isFFmpegActive
            ? (mkvCoordinator.playerLayer?.isPipActive == true) : pipManager.isPiPActive
          Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isPiPActive ? themeManager.accent : .white.opacity(0.85))
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
              Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .accessibilityLabel(
          (isFFmpegActive
            ? (mkvCoordinator.playerLayer?.isPipActive == true) : pipManager.isPiPActive)
            ? "Exit Picture in Picture" : "Enter Picture in Picture")
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
        .foregroundStyle(
          sleepTimerManager.isTimerActive ? themeManager.accent : .white.opacity(0.85)
        )
        .padding(.horizontal, sleepTimerManager.isTimerActive ? 8 : 0)
        .frame(height: 34)
        .frame(minWidth: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            sleepTimerManager.isTimerActive
              ? themeManager.accent.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 0.5)
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
          .foregroundStyle(isFavorite ? TipTVTheme.liveRed : .white.opacity(0.85))
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
        let progress =
          duration > 0 ? (isScrubbing ? scrubTime : currentTime) / effectiveDuration : 0
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
            .offset(
              x: max(
                0,
                min(
                  barWidth * CGFloat(clampedProgress) - (isScrubbing ? 8 : 5),
                  max(0, barWidth - (isScrubbing ? 16 : 10)))))
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
            .fill(isVODContent ? themeManager.accent : TipTVTheme.liveRed)
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
              Capsule().strokeBorder(
                playbackRate != 1.0 ? themeManager.accent.opacity(0.4) : Color.white.opacity(0.1),
                lineWidth: 0.5)
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
            Capsule().strokeBorder(
              isAspectFill ? themeManager.accent.opacity(0.4) : Color.white.opacity(0.1),
              lineWidth: 0.5)
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
    removeTimeObserver()
    timeObserverPlayer = player
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak player] time in
      guard let player else { return }
      if !self.isScrubbing {
        self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
      }
      if let itemDuration = player.currentItem?.duration,
        itemDuration.isValid && !itemDuration.isIndefinite
      {
        let sec = itemDuration.seconds
        if sec.isFinite && sec > 0 {
          self.duration = sec
        }
      }
    }
  }

  private func removeTimeObserver() {
    if let token = timeObserverToken {
      timeObserverPlayer?.removeTimeObserver(token)
      timeObserverToken = nil
    }
    timeObserverPlayer = nil
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

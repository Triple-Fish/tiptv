//
//  ChannelDetailView.swift
//  tiptv
//

import AVKit
import KSPlayer
import SwiftUI

struct ChannelDetailView: View {
  let channel: Channel
  let allChannels: [Channel]
  let player: AVPlayer?
  var isUsingKSPlayer: Bool = false
  var errorMessage: String? = nil
  var isLoadingStream: Bool = false
  var isPresentedFullScreen: Bool = false
  let onSelectChannel: (Channel) -> Void
  let onOpenFullScreen: () -> Void
  let onBack: () -> Void
  var onRetry: (() -> Void)? = nil
  var onTogglePlayerEngine: (() -> Void)? = nil

  @State private var favoritesManager = FavoritesManager.shared
  @ObservedObject private var themeManager = ThemeManager.shared
  @StateObject private var previewMkvCoordinator = KSVideoPlayer.Coordinator()
  @State private var showingGuideSheet = false
  @State private var relatedChannels: [Channel] = []

  private var isFavorite: Bool {
    favoritesManager.isFavorite(channel)
  }

  private var isVODContent: Bool {
    channel.isVOD || channel.category == .movies || channel.category == .series
  }

  private var isFFmpegPlayerActive: Bool {
    isUsingKSPlayer || channel.streamURLString.lowercased().contains(".mkv")
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 18) {
        // Top Custom Navigation Bar
        HStack {
          Button(action: {
            previewMkvCoordinator.playerLayer?.pause()
            previewMkvCoordinator.playerLayer?.stop()
            previewMkvCoordinator.resetPlayer()
            IdleTimerManager.setDisabled(false)
            onBack()
          }) {
            HStack(spacing: 6) {
              Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
              Text("Back")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1), in: Capsule())
          }
          .buttonStyle(.plain)

          Spacer()

          // Favorite Toggle Button
          Button {
            Haptics.light()
            withAnimation {
              favoritesManager.toggleFavorite(channel)
            }
          } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(isFavorite ? TipTVTheme.liveRed : .white)
              .frame(width: 38, height: 38)
              .background(Color.white.opacity(0.1), in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")

          // Fullscreen Expand Button
          Button(action: {
            previewMkvCoordinator.playerLayer?.pause()
            onOpenFullScreen()
          }) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 38, height: 38)
              .background(Color.white.opacity(0.1), in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Full Screen")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)

        // Inline Player / VOD Preview Window
        ZStack {
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(
              RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )

          if isVODContent {
            vodPictureView
          } else if isFFmpegPlayerActive {
            // Advanced FFmpeg / KSPlayer Engine for broadcast TS / MKV streams
            MKVPlayerView(
              url: channel.streamURL,
              coordinator: previewMkvCoordinator
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomTrailing) {
              Button(action: {
                previewMkvCoordinator.playerLayer?.pause()
                onOpenFullScreen()
              }) {
                Image(systemName: "viewfinder")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(.white)
                  .padding(8)
                  .background(Color.black.opacity(0.6), in: Circle())
                  .padding(10)
              }
              .buttonStyle(.plain)
            }
          } else if let player {
            PiPVideoPlayer(player: player, isAspectFill: false)
              .clipShape(RoundedRectangle(cornerRadius: 18))
          }

          if isLoadingStream {
            ZStack {
              Color.black.opacity(0.4)
              ProgressView()
                .tint(themeManager.accent)
                .scaleEffect(1.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
          }

          if let error = errorMessage {
            VStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
              Text(error)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

              if let onRetry {
                Button(action: onRetry) {
                  HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                  }
                  .font(.system(size: 12, weight: .bold, design: .rounded))
                  .foregroundStyle(.black)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 6)
                  .background(themeManager.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
              }
            }
          }
        }
        .padding(.horizontal, 20)

        // Channel Info Header
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 14) {
            ChannelArtwork(
              logoURL: channel.logoURL,
              channelName: channel.uniformName,
              size: 56,
              cornerRadius: 14
            )

            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 6) {
                if !isVODContent {
                  Circle()
                    .fill(TipTVTheme.liveRed)
                    .frame(width: 8, height: 8)
                  Text("LIVE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(TipTVTheme.liveRed)
                    .tracking(0.6)
                } else {
                  Text(channel.category == .series ? "SERIES" : "VOD")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(TipTVTheme.accent)
                    .tracking(0.6)
                }

                if let group = channel.group, !group.isEmpty {
                  Text("•")
                    .foregroundStyle(.white.opacity(0.4))
                  Text(group)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                }
              }

              Text(channel.uniformName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
            }
            Spacer()
          }

          // Content Tag Pills
          HStack(spacing: 8) {
            Label(channel.category.rawValue, systemImage: channel.category.icon)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundStyle(themeManager.accent)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(themeManager.accent.opacity(0.12), in: Capsule())

            if isFFmpegPlayerActive {
              Label("FFmpeg Engine", systemImage: "bolt.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
            }

            if !isVODContent {
              Button {
                showingGuideSheet = true
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                  Text("EPG Guide")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(TipTVTheme.aqua)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(TipTVTheme.aqua.opacity(0.12), in: Capsule())
              }
              .buttonStyle(.plain)
            }
          }

          // Action Controls: Fullscreen & Engine Switch
          HStack(spacing: 12) {
            Button(action: onOpenFullScreen) {
              HStack(spacing: 8) {
                Image(systemName: "play.fill")
                  .font(.system(size: 13, weight: .bold))
                Text("Play Full Screen")
                  .font(.system(size: 14, weight: .bold, design: .rounded))
              }
              .foregroundStyle(.black)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(themeManager.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let onTogglePlayerEngine, !isVODContent {
              Button(action: onTogglePlayerEngine) {
                HStack(spacing: 6) {
                  Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
                  Text(isFFmpegPlayerActive ? "Engine: FFmpeg" : "Engine: Native")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                  RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.top, 6)
        }
        .padding(.horizontal, 20)

        // Related / More Like This Section
        if !relatedChannels.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text(isVODContent ? "More Like This" : "More Channels in \(channel.category.rawValue)")
              .font(.system(size: 16, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
              LazyHStack(spacing: 12) {
                ForEach(relatedChannels) { related in
                  Button {
                    previewMkvCoordinator.playerLayer?.pause()
                    onSelectChannel(related)
                  } label: {
                    RelatedChannelCard(
                      channel: related,
                      isVOD: isVODContent
                    )
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.horizontal, 20)
            }
          }
          .padding(.top, 10)
        }

        Spacer(minLength: 80)
      }
    }
    .background(TipTVTheme.contentBackground.ignoresSafeArea())
    .task(id: channel.id) {
      let targetCategory = channel.category
      let currentID = channel.id
      let isVOD = isVODContent
      let found = await Task.detached(priority: .userInitiated) {
        var matches: [Channel] = []
        matches.reserveCapacity(10)
        let searchPool = allChannels.count > 300 ? Array(allChannels.prefix(300)) : allChannels
        for item in searchPool {
          if item.id != currentID && (item.category == targetCategory || (isVOD && item.isVOD)) {
            matches.append(item)
            if matches.count >= 10 { break }
          }
        }
        return matches
      }.value
      self.relatedChannels = found
    }
    .sheet(isPresented: $showingGuideSheet) {
      EPGGuideSheet(channel: channel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .onChange(of: isPresentedFullScreen) { _, isFullScreen in
      if isFullScreen {
        previewMkvCoordinator.playerLayer?.pause()
      } else if isFFmpegPlayerActive && !isVODContent {
        previewMkvCoordinator.playerLayer?.play()
      }
    }
    .onAppear {
      if isVODContent {
        IdleTimerManager.setDisabled(false)
      } else {
        IdleTimerManager.setDisabled(true)
      }
    }
    .onDisappear {
      previewMkvCoordinator.playerLayer?.pause()
      previewMkvCoordinator.playerLayer?.stop()
      previewMkvCoordinator.resetPlayer()
      IdleTimerManager.setDisabled(false)
    }
  }

  // MARK: - VOD Picture View

  private var vodPictureView: some View {
    Button(action: {
      previewMkvCoordinator.playerLayer?.pause()
      onOpenFullScreen()
    }) {
      ZStack {
        Color.black

        if let logo = channel.logoURL {
          DetailCachedImage(url: logo) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
              .padding(12)
          } placeholder: {
            vodPlaceholder
          }
        } else {
          vodPlaceholder
        }

        LinearGradient(
          colors: [.clear, Color.black.opacity(0.65)],
          startPoint: .top,
          endPoint: .bottom
        )

        // Center Play Icon Button Overlay
        VStack {
          Spacer()
          HStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 42, weight: .light))
              .foregroundStyle(themeManager.accent)
              .shadow(color: themeManager.accent.opacity(0.5), radius: 10)
          }
          Spacer()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    .buttonStyle(.plain)
  }

  private var vodPlaceholder: some View {
    VStack(spacing: 12) {
      Image(systemName: channel.category == .series ? "tv" : "film")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(themeManager.accent.opacity(0.7))

      Text(channel.uniformName)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
  }
}

// MARK: - Fast Cached Artwork Loader (Ensures IPTV User-Agent & Coalescing)

private struct DetailCachedImage<Content: View, Placeholder: View>: View {
  let url: URL?
  @ViewBuilder let content: (Image) -> Content
  @ViewBuilder let placeholder: () -> Placeholder

  @State private var uiImage: UIImage?
  @State private var loadTask: Task<Void, Never>?

  var body: some View {
    Group {
      if let uiImage {
        content(Image(uiImage: uiImage))
      } else {
        placeholder()
      }
    }
    .onAppear {
      loadImage()
    }
    .onChange(of: url) { _, _ in
      loadImage()
    }
    .onDisappear {
      loadTask?.cancel()
      loadTask = nil
    }
  }

  private func loadImage() {
    guard let url else {
      uiImage = nil
      return
    }
    if let cached = ImageCacheManager.shared.image(for: url) {
      uiImage = cached
      return
    }
    loadTask?.cancel()
    loadTask = Task {
      let loaded = await ImageCacheManager.shared.loadImage(from: url)
      guard !Task.isCancelled else { return }
      if let loaded {
        self.uiImage = loaded
      }
    }
  }
}

// MARK: - Related Channel Card

private struct RelatedChannelCard: View {
  let channel: Channel
  let isVOD: Bool
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.white.opacity(0.06))
          .frame(width: isVOD ? 110 : 130, height: isVOD ? 160 : 80)

        if let logo = channel.logoURL {
          DetailCachedImage(url: logo) { img in
            img
              .resizable()
              .aspectRatio(contentMode: isVOD ? .fill : .fit)
              .frame(width: isVOD ? 110 : 130, height: isVOD ? 160 : 80)
              .clipped()
              .cornerRadius(10)
          } placeholder: {
            cardPlaceholder
          }
        } else {
          cardPlaceholder
        }
      }
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
      )

      Text(channel.uniformName)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(width: isVOD ? 110 : 130, alignment: .leading)
    }
  }

  private var cardPlaceholder: some View {
    VStack(spacing: 4) {
      Image(systemName: isVOD ? "film" : "tv")
        .font(.system(size: 18))
        .foregroundStyle(themeManager.accent.opacity(0.6))
      Text(channel.uniformName)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
    }
  }
}

// MARK: - EPG Guide Sheet

private struct EPGGuideSheet: View {
  let channel: Channel
  @Environment(\.dismiss) private var dismiss
  @State private var epgManager = EPGManager.shared
  @State private var reminderManager = ProgrammeReminderManager.shared

  private var programs: [EPGProgram] {
    epgManager.programs(for: channel)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("Now Playing") {
          if let current = epgManager.currentProgram(for: channel) {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("LIVE")
                  .font(.system(size: 10, weight: .bold, design: .rounded))
                  .foregroundStyle(TipTVTheme.liveRed)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(TipTVTheme.liveRed.opacity(0.15), in: Capsule())

                Text(current.title)
                  .font(.headline)
              }

              Text(current.timeRangeString)
                .font(.caption)
                .foregroundStyle(.secondary)

              if !current.synopsis.isEmpty {
                Text(current.synopsis)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 4)
          } else {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("NOW")
                  .font(.system(size: 10, weight: .bold, design: .rounded))
                  .foregroundStyle(TipTVTheme.liveRed)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(TipTVTheme.liveRed.opacity(0.15), in: Capsule())

                Text("Live Broadcast")
                  .font(.headline)
              }

              Text(channel.uniformName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
        }

        if !programs.isEmpty {
          Section("Schedule") {
            ForEach(programs) { prog in
              HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(prog.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                  if !prog.synopsis.isEmpty {
                    Text(prog.synopsis)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                }
                Spacer()
                Text(prog.timeRangeString)
                  .font(.system(size: 11, weight: .medium, design: .monospaced))
                  .foregroundStyle(.secondary)
                if prog.startTime > Date() {
                  Button {
                    Task { await reminderManager.toggle(program: prog, channel: channel) }
                  } label: {
                    Image(systemName: reminderManager.hasReminder(for: prog) ? "bell.fill" : "bell")
                      .foregroundStyle(
                        reminderManager.hasReminder(for: prog) ? TipTVTheme.aqua : .secondary)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel(
                    reminderManager.hasReminder(for: prog) ? "Remove reminder" : "Remind me")
                }
              }
              .padding(.vertical, 2)
            }
          }
        }

        if epgManager.isLoading {
          Section { ProgressView("Updating programme guide…") }
        } else if programs.isEmpty {
          Section {
            ContentUnavailableView(
              "No Guide Data",
              systemImage: "calendar.badge.exclamationmark",
              description: Text(
                "Add an XMLTV URL to the active playlist profile, then reload the playlist.")
            )
          }
        }

        Section("Channel Details") {
          LabeledContent("Category", value: channel.category.rawValue)
          if let group = channel.group {
            LabeledContent("Playlist Group", value: group)
          }
          LabeledContent("Stream URL", value: channel.streamURL.host ?? "Unknown")
        }
      }
      .navigationTitle("Program Guide")
      .inlineNavigationBarTitle()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

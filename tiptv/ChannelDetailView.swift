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

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var previewMkvCoordinator = KSVideoPlayer.Coordinator()
    @State private var showingGuideSheet = false

    private var isFavorite: Bool {
        favoritesManager.isFavorite(channel)
    }

    private var isVODContent: Bool {
        channel.isVOD || channel.category == .movies || channel.category == .series
    }

    private var isFFmpegPlayerActive: Bool {
        isUsingKSPlayer || channel.streamURLString.lowercased().contains(".mkv")
    }

    private var relatedChannels: [Channel] {
        Array(
            allChannels.lazy
                .filter { $0.id != channel.id && ($0.category == channel.category || (isVODContent && $0.isVOD)) }
                .prefix(10)
        )
    }

    private var channelDescription: String {
        if channel.isSeries || channel.category == .series {
            if let group = channel.group, !group.isEmpty {
                return "Watch \(channel.uniformName) on demand from \(group)."
            }
            return "Watch \(channel.uniformName) on demand."
        }
        if channel.isMovie || channel.category == .movies {
            if let group = channel.group, !group.isEmpty {
                return "Watch \(channel.uniformName) from \(group)."
            }
            return "Watch \(channel.uniformName) in full cinematic HD."
        }
        if let current = EPGManager.shared.currentProgram(for: channel) {
            return current.synopsis.isEmpty ? current.title : current.synopsis
        }
        if let group = channel.group, !group.isEmpty {
            return "Live television broadcast from \(group). Tap to stream in full resolution."
        }
        return "High-definition live TV broadcast stream. Enjoy seamless playback on tiptv."
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Top Custom Navigation Bar
                HStack {
                    Button(action: {
                        previewMkvCoordinator.playerLayer?.pause()
                        previewMkvCoordinator.resetPlayer()
                        onBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Back")

                    Spacer()

                    Button {
                        Haptics.medium()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            favoritesManager.toggleFavorite(channel)
                        }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFavorite ? tiptvTheme.liveRed : .white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // 16:9 Video Player Preview or Movie Picture Card
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black)

                    if isVODContent {
                        vodPictureView
                    } else if isFFmpegPlayerActive {
                        if !isPresentedFullScreen {
                            MKVPlayerView(url: channel.streamURL, coordinator: previewMkvCoordinator)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(0.05))
                        }
                    } else if let player, !isPresentedFullScreen {
                        PiPVideoPlayer(player: player, isAspectFill: true)
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.05))
                    }

                    if !isVODContent {
                        if let errorMessage, !isFFmpegPlayerActive {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.orange)

                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)

                                if let onRetry {
                                    Button(action: {
                                        previewMkvCoordinator.playerLayer?.pause()
                                        previewMkvCoordinator.resetPlayer()
                                        onRetry()
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("Retry")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(themeManager.accent, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                            .padding(16)
                        } else if isLoadingStream && !isFFmpegPlayerActive {
                            ProgressView()
                                .tint(themeManager.accent)
                                .scaleEffect(1.2)
                        }

                        // Top & Bottom Overlays in corner (for live channels)
                        VStack {
                            // Top Row: Engine Toggle Badge
                            HStack {
                                if let onTogglePlayerEngine {
                                    Button(action: {
                                        previewMkvCoordinator.playerLayer?.pause()
                                        previewMkvCoordinator.resetPlayer()
                                        onTogglePlayerEngine()
                                    }) {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(isFFmpegPlayerActive ? themeManager.accent : tiptvTheme.aqua)
                                                .frame(width: 6, height: 6)
                                            Text(isFFmpegPlayerActive ? "FFmpeg" : "Native")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                                        )
                                    }
                                    .accessibilityLabel("Toggle Player Engine (Currently \(isFFmpegPlayerActive ? "FFmpeg" : "Native"))")
                                }

                                Spacer()
                            }
                            .padding(10)

                            Spacer()

                            // Bottom Row: PiP & Fullscreen
                            HStack {
                                Spacer()

                                if PiPManager.shared.isSupported {
                                    Button {
                                        Haptics.medium()
                                        PiPManager.shared.togglePiP()
                                    } label: {
                                        Image(systemName: "pip.enter")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                    }
                                }

                                Button(action: {
                                    previewMkvCoordinator.playerLayer?.pause()
                                    previewMkvCoordinator.resetPlayer()
                                    onOpenFullScreen()
                                }) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                }
                            }
                            .padding(10)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .padding(.horizontal, 20)
                .shadow(color: Color.black.opacity(0.4), radius: 16, y: 6)

                // Channel Info
                VStack(alignment: .leading, spacing: 8) {
                    // Badge
                    HStack(spacing: 5) {
                        if channel.isSeries || channel.category == .series {
                            Image(systemName: "tv.inset.filled")
                                .font(.system(size: 9))
                                .foregroundStyle(themeManager.accent)

                            Text("SERIES")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(themeManager.accent)
                        } else if channel.isMovie || channel.category == .movies {
                            Image(systemName: "film.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(themeManager.accent)

                            Text("MOVIE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(themeManager.accent)
                        } else {
                            Circle()
                                .fill(tiptvTheme.liveRed)
                                .frame(width: 6, height: 6)

                            Text("LIVE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(tiptvTheme.liveRed)
                        }

                        if isFavorite {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                Text("FAVORITE")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(tiptvTheme.liveRed)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tiptvTheme.liveRed.opacity(0.15), in: Capsule())
                        }
                    }

                    // Title
                    Text(channel.uniformName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Subtitle (Category & Group)
                    HStack(spacing: 6) {
                        Text(channel.category.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))

                        if let group = channel.group, !group.isEmpty {
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 3, height: 3)

                            Text(group)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }

                    // Description / EPG
                    Text(channelDescription)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(3)
                        .padding(.top, 2)

                    // Action Buttons (Full Screen, EPG Guide, Favorite)
                    HStack(spacing: 10) {
                        Button(action: {
                            previewMkvCoordinator.playerLayer?.pause()
                            previewMkvCoordinator.resetPlayer()
                            onOpenFullScreen()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Full Screen")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(themeManager.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        if !isVODContent {
                            Button {
                                Haptics.light()
                                showingGuideSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.clock")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Guide")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                                        previewMkvCoordinator.resetPlayer()
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
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .sheet(isPresented: $showingGuideSheet) {
            EPGGuideSheet(channel: channel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - VOD Picture View

    private var vodPictureView: some View {
        Button(action: {
            previewMkvCoordinator.playerLayer?.pause()
            previewMkvCoordinator.resetPlayer()
            onOpenFullScreen()
        }) {
            ZStack {
                Color.black

                if let logo = channel.logoURL {
                    AsyncImage(url: logo) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(12)
                        case .failure:
                            vodPlaceholder
                        case .empty:
                            ProgressView()
                                .tint(themeManager.accent)
                        @unknown default:
                            vodPlaceholder
                        }
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
                    AsyncImage(url: logo) { phase in
                        switch phase {
                        case .success(let img):
                            img
                                .resizable()
                                .aspectRatio(contentMode: isVOD ? .fill : .fit)
                                .frame(width: isVOD ? 110 : 130, height: isVOD ? 160 : 80)
                                .clipped()
                                .cornerRadius(10)
                        default:
                            cardPlaceholder
                        }
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

    private var programs: [EPGProgram] {
        EPGManager.shared.programs(for: channel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Now Playing") {
                    if let current = EPGManager.shared.currentProgram(for: channel) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(tiptvTheme.liveRed)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tiptvTheme.liveRed.opacity(0.15), in: Capsule())

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
                                    .foregroundStyle(tiptvTheme.liveRed)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tiptvTheme.liveRed.opacity(0.15), in: Capsule())

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
                            HStack(alignment: .top) {
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
                            }
                            .padding(.vertical, 2)
                        }
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

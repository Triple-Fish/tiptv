//
//  HomeView.swift
//  tiptv
//

import SwiftUI

enum HomeSheet: Identifiable {
    case search
    case settings
    case paywall

    var id: Int {
        switch self {
        case .search: return 1
        case .settings: return 2
        case .paywall: return 3
        }
    }
}

struct HomeView: View {
    let channels: [Channel]
    let allChannels: [Channel]
    let onSelectChannel: (Channel) -> Void
    let onSelectCategory: (NetflixCategory) -> Void
    let onReloadPlaylist: () -> Void
    let onDeletePlaylist: () -> Void
    let onAddPlaylist: () -> Void

    @AppStorage("playlistURL") private var playlistURL = ""
    @AppStorage("playlistUsername") private var playlistUsername = ""
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var activeSheet: HomeSheet?
    @State private var favoriteChannels: [Channel] = []
    @State private var featuredChannels: [Channel] = []
    @State private var sportsChannels: [Channel] = []
    @State private var movieChannels: [Channel] = []

    private func updateSubsets() {
        // Bounded scan of first 1000 items ensures 60/120fps UI responsiveness even with 50k+ channels
        let scanSlice = channels.count > 1000 ? Array(channels.prefix(1000)) : channels
        favoriteChannels = favoritesManager.filterFavorites(from: scanSlice)
        featuredChannels = Array(scanSlice.prefix(12))

        var sports: [Channel] = []
        var movies: [Channel] = []
        sports.reserveCapacity(8)
        movies.reserveCapacity(8)

        for ch in scanSlice {
            if ch.category == .sports && sports.count < 8 {
                sports.append(ch)
            } else if (ch.category == .movies || ch.isMovie) && movies.count < 8 {
                let movieItem = ch.category == .movies ? ch : Channel(
                    id: ch.id,
                    name: ch.name,
                    uniformName: ch.uniformName,
                    group: ch.group,
                    logoURL: ch.logoURL,
                    streamURL: ch.streamURL,
                    streamURLString: ch.streamURLString,
                    category: .movies
                )
                movies.append(movieItem)
            }
            if sports.count >= 8 && movies.count >= 8 {
                break
            }
        }
        sportsChannels = sports
        movieChannels = movies
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Top Brand Bar (Outside ScrollView for instant tap responsiveness)
            HStack {
                HStack(spacing: 10) {
                    tiptvBrandLogo(size: 26)

                    if !licenseManager.hasPurchasedLicense {
                        Button {
                            Haptics.light()
                            activeSheet = .paywall
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: licenseManager.isTrialActive ? "clock.fill" : "lock.fill")
                                    .font(.system(size: 9))
                                Text(licenseManager.isTrialActive ? licenseManager.trialTimeRemainingString : "Upgrade")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(licenseManager.isTrialActive ? tiptvTheme.aqua : tiptvTheme.liveRed)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (licenseManager.isTrialActive ? tiptvTheme.aqua : tiptvTheme.liveRed).opacity(0.14),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        activeSheet = .search
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search Channels")

                    Button {
                        Haptics.light()
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(tiptvTheme.contentBackground)

            // Scrollable Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Hero Banner Card
                HeroBannerCard(
                    channelCount: channels.count,
                    onWatchNow: {
                        if let first = channels.first {
                            onSelectChannel(first)
                        }
                    },
                    onAddPlaylist: onAddPlaylist
                )
                .padding(.horizontal, 20)

                // Live TV Quick Category Tiles
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Live TV")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Button("See All") {
                            onSelectCategory(.all)
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 10) {
                        QuickCategoryTile(
                            icon: "sportscourt",
                            title: "Sports",
                            action: { onSelectCategory(.sports) }
                        )

                        QuickCategoryTile(
                            icon: "newspaper",
                            title: "News",
                            action: { onSelectCategory(.news) }
                        )

                        QuickCategoryTile(
                            icon: "film",
                            title: "Movies",
                            action: { onSelectCategory(.movies) }
                        )

                        QuickCategoryTile(
                            icon: "face.smiling",
                            title: "Kids",
                            action: { onSelectCategory(.kids) }
                        )
                    }
                    .padding(.horizontal, 20)
                }

                // My Favorites Row (visible when user has favorited channels)
                if !favoriteChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(tiptvTheme.liveRed)

                                Text("My Favorites")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Text("\(favoriteChannels.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(tiptvTheme.liveRed)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tiptvTheme.liveRed.opacity(0.16), in: Capsule())
                            }

                            Spacer()

                            Button("See All") {
                                onSelectCategory(.favorites)
                            }
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(favoriteChannels) { channel in
                                    Button {
                                        onSelectChannel(channel)
                                    } label: {
                                        UniformChannelBoxCard(channel: channel, boxSize: 84, cornerRadius: 18, isFavorite: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                // Featured Channels Horizontal Row
                if !featuredChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Featured")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            Button("See All") {
                                onSelectCategory(.all)
                            }
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(featuredChannels) { channel in
                                    Button {
                                        onSelectChannel(channel)
                                    } label: {
                                        UniformChannelBoxCard(
                                            channel: channel,
                                            boxSize: 84,
                                            cornerRadius: 18,
                                            isFavorite: favoritesManager.isFavorite(channel)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                // Sports Row
                if !sportsChannels.isEmpty {
                    ChannelRowSection(
                        title: "Sports Live",
                        channels: sportsChannels,
                        onSeeAll: { onSelectCategory(.sports) },
                        onSelectChannel: onSelectChannel
                    )
                }

                // Movies Row
                if !movieChannels.isEmpty {
                    ChannelRowSection(
                        title: "Top Movies",
                        channels: movieChannels,
                        onSeeAll: { onSelectCategory(.movies) },
                        onSelectChannel: onSelectChannel
                    )
                }
            }
            .padding(.bottom, 24)
        }
    }
    .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .search:
                ChannelSearchView(
                    channels: channels,
                    onSelectChannel: onSelectChannel
                )
            case .settings:
                SettingsView(
                    playlistURL: $playlistURL,
                    username: $playlistUsername,
                    totalChannels: channels.count,
                    allChannels: allChannels,
                    onReload: onReloadPlaylist,
                    onDelete: onDeletePlaylist,
                    onOpenImporter: onAddPlaylist,
                    onDismiss: { activeSheet = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .tint(themeManager.accent)
                .preferredColorScheme(.dark)

            case .paywall:
                PaywallView(onDismiss: {
                    activeSheet = nil
                })
            }
        }
        .onAppear {
            updateSubsets()
        }
        .onChange(of: channels.count) { _, _ in
            updateSubsets()
        }
        .onChange(of: channels.first?.id) { _, _ in
            updateSubsets()
        }
        .onReceive(favoritesManager.$favoriteStreamURLs) { _ in
            updateSubsets()
        }
    }
}

// MARK: - Hero Banner Card

private struct HeroBannerCard: View {
    let channelCount: Int
    let onWatchNow: () -> Void
    let onAddPlaylist: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Background Artwork
            tiptvTheme.heroGradient

            // Abstract ambient curved glow matching icon teal
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tiptvTheme.accent.opacity(0.45), tiptvTheme.aqua.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: 160, y: -40)
                .blur(radius: 20)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Live Tag
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("LIVE TV")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12), in: Capsule())

                // Title
                Text(channelCount > 0 ? "Thousands of Channels" : "Welcome to tiptv")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Subtitle
                Text(channelCount > 0 ? "Sports, News, Movies, Kids and more." : "Add a playlist to begin streaming.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                // Action Button
                Button(action: channelCount > 0 ? onWatchNow : onAddPlaylist) {
                    HStack(spacing: 6) {
                        Image(systemName: channelCount > 0 ? "play.fill" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(channelCount > 0 ? "Watch Now" : "Add Playlist")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 14, y: 6)
    }
}

// MARK: - Quick Category Tile

private struct QuickCategoryTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(height: 24)

                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tiptvTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tiptvTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Uniform Channel Box Card (Identical box around icon across all channels)

struct UniformChannelBoxCard: View {
    let channel: Channel
    var boxSize: CGFloat = 84
    var cornerRadius: CGFloat = 18
    var isFavorite: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ChannelArtwork(
                logoURL: channel.logoURL,
                channelName: channel.uniformName,
                size: boxSize,
                cornerRadius: cornerRadius
            )

            Text(channel.uniformName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: boxSize, height: 28, alignment: .top)
        }
        .frame(width: boxSize)
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
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }
}

// MARK: - Channel Row Section

private struct ChannelRowSection: View {
    let title: String
    let channels: [Channel]
    let onSeeAll: () -> Void
    let onSelectChannel: (Channel) -> Void

    @ObservedObject private var favoritesManager = FavoritesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button("See All", action: onSeeAll)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(channels) { channel in
                        Button {
                            onSelectChannel(channel)
                        } label: {
                            UniformChannelBoxCard(
                                channel: channel,
                                boxSize: 84,
                                cornerRadius: 18,
                                isFavorite: favoritesManager.isFavorite(channel)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

//
//  MoviesCatalogView.swift
//  tiptv
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MoviesCatalogView: View {
    let items: [Channel]
    let title: String
    var isLoading: Bool = false
    let onSelectChannel: (Channel) -> Void
    var onReload: (() -> Void)? = nil

    init(
        items: [Channel],
        title: String,
        isLoading: Bool = false,
        onSelectChannel: @escaping (Channel) -> Void,
        onReload: (() -> Void)? = nil
    ) {
        self.items = items
        self.title = title
        self.isLoading = isLoading
        self.onSelectChannel = onSelectChannel
        self.onReload = onReload
    }

    @ObservedObject private var themeManager = ThemeManager.shared
    enum VideoFormatFilter: String, CaseIterable, Identifiable {
        case all = "All Formats"
        case mp4 = "MP4"
        case mkv = "MKV"

        var id: String { rawValue }
    }

    @AppStorage("playlistURL") private var playlistURL = ""
    @State private var credentials = PlaylistCredentials.shared
    @State private var continueWatching = ContinueWatchingManager.shared
    @State private var selectedSeries: Channel? = nil
    @State private var selectedFormat: VideoFormatFilter = .all
    @State private var selectedGroup: String = "All"
    @State private var cachedGroups: [String] = ["All"]
    @State private var displayLimit = 120

    private var availableGroups: [String] {
        cachedGroups
    }

    @State private var filteredItems: [Channel] = []
    @State private var filterTask: Task<Void, Never>?

    private var featuredItem: Channel? {
        filteredItems.first
    }

    private func performFilter() {
        let currentItems = items
        let format = selectedFormat
        let grp = selectedGroup
        let isMovies = (title == "Movies")

        filterTask?.cancel()
        filterTask = Task {
            let work = Task.detached(priority: .userInitiated) {
            let requiredExtension: String? = isMovies && format != .all ? format.rawValue.lowercased() : nil
            let requiredGroup = grp == "All" ? nil : grp
                return ChannelCatalog.videoChannels(
                in: currentItems,
                group: requiredGroup,
                pathExtension: requiredExtension,
                query: ""
            )
            }
            let result = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }

            guard !Task.isCancelled else { return }
            self.filteredItems = result
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                let resumable = continueWatching.entries.filter { entry in
                    title == "Series" ? entry.channel.isSeries : entry.channel.isMovie
                }
                if !resumable.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Continue Watching")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(resumable.prefix(12)) { entry in
                                        Button { onSelectChannel(entry.channel) } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                MovieArtworkView(
                                                    logoURL: entry.channel.logoURL,
                                                    title: entry.channel.uniformName,
                                                    isSeries: entry.channel.isSeries
                                                )
                                                    .frame(width: 150, height: 84)
                                                    .clipped()
                                                    .background(Color.white.opacity(0.08))
                                                ProgressView(value: entry.progress)
                                                    .tint(themeManager.accent)
                                                Text(entry.channel.uniformName)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 150)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                }

                // Format Filter Bar (Movies only: MP4 direct vs MKV external)
                if title == "Movies" {
                    HStack(spacing: 8) {
                        ForEach(VideoFormatFilter.allCases) { filter in
                            let isSelected = selectedFormat == filter
                            Button {
                                #if canImport(UIKit)
                                Haptics.selection()
                                #endif
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedFormat = filter
                                    displayLimit = 120
                                    performFilter()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if filter == .mp4 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                    }
                                    Text(filter.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                }
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? themeManager.accent : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                }

                // Genre / Group Pills (if multiple groups exist)
                if availableGroups.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(availableGroups, id: \.self) { group in
                                let isSelected = selectedGroup == group
                                Button {
                                    #if canImport(UIKit)
                                    Haptics.selection()
#endif
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedGroup = group
                                    }
                                } label: {
                                    Text(group)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            isSelected ? themeManager.accent : Color.white.opacity(0.08),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Empty State, Loading, or Content Grid
                if isLoading && items.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(themeManager.accent)
                            .scaleEffect(1.2)
                            .padding(.top, 40)
                        Text("Loading \(title.lowercased()) catalog...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    emptyStateView
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.top, 40)
                        Text("No matching \(title.lowercased()) found")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))

                    }
                } else {
                    // Featured Hero Poster Card
                    if let item = featuredItem, selectedGroup == "All" {
                        featuredHeroCard(item: item)
                    }

                    // Poster Grid (2:3 aspect ratio cards)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(selectedGroup == "All" ? "All \(title)" : selectedGroup)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 16
                        ) {
                            ForEach(filteredItems.prefix(displayLimit)) { item in
                                MoviePosterCard(item: item) {
                                    handleItemSelection(item)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        if filteredItems.count > displayLimit {
                            Button {
                                displayLimit = min(displayLimit + 120, filteredItems.count)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load More (\(filteredItems.count - displayLimit) remaining)")
                                }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(themeManager.accent)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .tint(themeManager.accent)
                        .scaleEffect(0.8)
                }

                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeManager.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(themeManager.accent.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(themeManager.accent.opacity(0.25), lineWidth: 0.5)
                        )
                }

                if let onReload {
                    Button(action: onReload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Reload \(title)")
                }
            }
        }
        .task(id: items.count) {
            guard !items.isEmpty else {
                cachedGroups = ["All"]
                filteredItems = []
                return
            }

            let (sortedGroups, initialFiltered) = await Task.detached(priority: .userInitiated) {
                var groups = Set<String>()
                for item in items {
                    if let group = item.group, !group.isEmpty {
                        groups.insert(group)
                    }
                }
                return (["All"] + groups.sorted(), items)
            }.value

            cachedGroups = sortedGroups
            if selectedGroup == "All" && selectedFormat == .all {
                filteredItems = initialFiltered
            } else {
                performFilter()
            }
        }
        .onChange(of: selectedGroup) { _, _ in
            displayLimit = 120
            performFilter()
        }
        .sheet(item: $selectedSeries) { seriesItem in
            SeriesDetailView(
                series: seriesItem,
                baseURL: playlistURL,
                username: credentials.username,
                password: credentials.password,
                onPlayEpisode: { episodeChannel in
                    selectedSeries = nil
                    onSelectChannel(episodeChannel)
                },
                onDismiss: {
                    selectedSeries = nil
                }
            )
        }
    }

    private func handleItemSelection(_ item: Channel) {
        if title == "Series" {
            selectedSeries = item
        } else {
            let movieItem = Channel(
                id: item.id,
                name: item.name,
                uniformName: item.uniformName,
                group: item.group,
                logoURL: item.logoURL,
                streamURL: item.streamURL,
                streamURLString: item.streamURLString,
                category: .movies
            )
            onSelectChannel(movieItem)
        }
    }

    // MARK: - Featured Hero Card

    private func featuredHeroCard(item: Channel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))

                    MovieArtworkView(
                        logoURL: item.logoURL,
                        title: item.uniformName,
                        isSeries: title == "Series"
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.uniformName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(title == "Series" ? "TV Series" : "Movie")
                            .font(.system(size: 11, weight: .medium, design: .rounded))

                        if let group = item.group {
                            Text("•")
                            Text(group)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }

                        Text("•")
                        Text("HD")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )

            // Play / View Episodes Button & Favorite Button
            HStack(spacing: 10) {
                Button {
                    #if canImport(UIKit)
                    Haptics.medium()
                    #endif
                    handleItemSelection(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: title == "Series" ? "list.bullet" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(title == "Series" ? "View Episodes" : "Play Now")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(themeManager.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                let isFav = FavoritesManager.shared.isFavorite(item)
                Button {
                    #if canImport(UIKit)
                    Haptics.light()
                    #endif
                    withAnimation {
                        FavoritesManager.shared.toggleFavorite(item)
                    }
                } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFav ? tiptvTheme.liveRed : .white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFav ? "Remove from Favourites" : "Add to Favourites")
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: title == "Series" ? "tv" : "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.accent.opacity(0.6))
                .padding(.top, 40)

            Text("No On-Demand \(title) Available")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your current playlist provides Live TV channels. If your IPTV provider supports on-demand \(title.lowercased()), ensure your account has VOD enabled.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onReload {
                Button(action: onReload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Check for \(title)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Series Detail View & Episode Browser

struct SeriesDetailView: View {
    let series: Channel
    let baseURL: String
    let username: String
    let password: String
    let onPlayEpisode: (Channel) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var favoritesManager = FavoritesManager.shared
    @State private var seriesInfo: XtreamSeriesInfo? = nil
    @State private var selectedSeason: Int = 1
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private var seriesID: String {
        let lastPart = series.streamURL.deletingPathExtension().lastPathComponent
        return lastPart.isEmpty ? series.name : lastPart
    }

    private var currentSeasonEpisodes: [XtreamEpisode] {
        seriesInfo?.episodesBySeason[selectedSeason] ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tiptvTheme.contentBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Backdrop Header or Poster Card
                        headerView

                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(themeManager.accent)
                                    .scaleEffect(1.2)
                                Text("Loading series episodes...")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                        } else if let error = errorMessage {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Button {
                                    loadEpisodes()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry")
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(themeManager.accent, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                        } else {

                            // Quick Play Episode 1 Button
                            if let firstEp = seriesInfo?.episodesBySeason[seriesInfo?.seasons.first ?? 1]?.first {
                                Button {
                                    #if canImport(UIKit)
                                    Haptics.medium()
                                    #endif
                                    playEpisode(firstEp)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Play \(firstEp.title)")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(themeManager.accent, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 20)
                            }

                            // Season Tabs
                            if let seasons = seriesInfo?.seasons, seasons.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(seasons, id: \.self) { season in
                                            let isSelected = selectedSeason == season
                                            Button {
                                                #if canImport(UIKit)
                                                Haptics.selection()
                                                #endif
                                                selectedSeason = season
                                            } label: {
                                                Text("Season \(season)")
                                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                                    .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        isSelected ? themeManager.accent : Color.white.opacity(0.08),
                                                        in: Capsule()
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }

                            // Episodes List
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Season \(selectedSeason) Episodes (\(currentSeasonEpisodes.count))")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)

                                if currentSeasonEpisodes.isEmpty {
                                    Text("No episodes available for this season.")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                } else {
                                    LazyVStack(spacing: 10) {
                                        ForEach(currentSeasonEpisodes) { ep in
                                            episodeRow(ep)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        IdleTimerManager.setDisabled(false)
                        onDismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    let isFavorite = favoritesManager.isFavorite(series)
                    Button {
                        #if canImport(UIKit)
                        Haptics.light()
                        #endif
                        withAnimation {
                            favoritesManager.toggleFavorite(series)
                        }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isFavorite ? tiptvTheme.liveRed : .white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
            }
        }
        .onAppear {
            IdleTimerManager.setDisabled(false)
        }
        .onDisappear {
            IdleTimerManager.setDisabled(false)
        }
        .task {
            loadEpisodes()
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Poster
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))

                    MovieArtworkView(
                        logoURL: seriesInfo?.coverURL ?? series.logoURL,
                        title: series.uniformName,
                        isSeries: true
                    )
                }
                .frame(width: 105, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

                // Info details
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(seriesInfo?.name ?? series.uniformName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)

                        Spacer()

                        let isFavorite = favoritesManager.isFavorite(series)
                        Button {
                            #if canImport(UIKit)
                            Haptics.light()
                            #endif
                            withAnimation {
                                favoritesManager.toggleFavorite(series)
                            }
                        } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isFavorite ? tiptvTheme.liveRed : .white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }

                    if let genre = seriesInfo?.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(themeManager.accent)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let rating = seriesInfo?.rating, !rating.isEmpty, rating != "0" {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.yellow)
                                Text(rating)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }

                        if let releaseDate = seriesInfo?.releaseDate, !releaseDate.isEmpty {
                            Text(releaseDate.prefix(4))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if let seasonsCount = seriesInfo?.seasons.count, seasonsCount > 0 {
                            Text("\(seasonsCount) Season\(seasonsCount == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    if let cast = seriesInfo?.cast, !cast.isEmpty {
                        Text("Cast: \(cast)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Plot
            if let plot = seriesInfo?.plot, !plot.isEmpty {
                Text(plot)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(4)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func episodeRow(_ ep: XtreamEpisode) -> some View {
        Button {
            #if canImport(UIKit)
            Haptics.medium()
            #endif
            playEpisode(ep)
        } label: {
            HStack(spacing: 12) {
                // Episode Number badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                    Text("\(ep.episodeNum)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.accent)
                }
                .frame(width: 44, height: 44)

                // Title & info
                VStack(alignment: .leading, spacing: 3) {
                    Text(ep.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if let duration = ep.duration, !duration.isEmpty {
                            Text(duration)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Text(ep.containerExtension.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(themeManager.accent.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(themeManager.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                Spacer()

                // Play icon button
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(themeManager.accent)
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func playEpisode(_ episode: XtreamEpisode) {
        SeriesPlaybackManager.shared.configureQueue(
            series: series,
            seriesInfo: seriesInfo,
            startingWith: episode
        )
        let epChannel = SeriesPlaybackManager.shared.channel(
            for: episode,
            series: series,
            coverURL: seriesInfo?.coverURL
        )
        onPlayEpisode(epChannel)
    }

    private func loadEpisodes() {
        isLoading = true
        errorMessage = nil
        Task {
            let info = await XtreamService.fetchSeriesInfo(
                baseURL: baseURL,
                username: username,
                password: password,
                seriesID: seriesID
            )
            await MainActor.run {
                self.seriesInfo = info
                self.selectedSeason = info?.seasons.first ?? 1
                if info == nil {
                    self.errorMessage = "Failed to load episodes. Please check your connection."
                }
                self.isLoading = false
            }
        }
    }
}


// MARK: - Movie / Series Poster Card

struct MoviePosterCard: View {
    let item: Channel
    let onSelect: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var favoritesManager = FavoritesManager.shared

    private var isMP4: Bool {
        item.streamURLString.lowercased().contains(".mp4")
    }

    var body: some View {
        Button {
            #if canImport(UIKit)
            Haptics.medium()
            #endif
            onSelect()
        } label: {
            VStack(alignment: .center, spacing: 6) {
                // 2:3 Portrait Poster Card Box with Thumbnail Centered in the Middle
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))

                    MovieArtworkView(
                        logoURL: item.logoURL,
                        title: item.uniformName,
                        isSeries: item.isSeries || item.category == .series
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 155)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .overlay(alignment: .topTrailing) {
                    Text(isMP4 ? "MP4" : "MKV")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(isMP4 ? .black : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isMP4 ? themeManager.accent : Color.black.opacity(0.75),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if favoritesManager.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tiptvTheme.liveRed)
                            .padding(5)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .padding(6)
                    }
                }

                Text(item.uniformName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32, alignment: .top)

                if let group = item.group {
                    Text(group)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            let isFav = favoritesManager.isFavorite(item)
            Button(role: isFav ? .destructive : nil) {
                #if canImport(UIKit)
                Haptics.light()
                #endif
                withAnimation {
                    favoritesManager.toggleFavorite(item)
                }
            } label: {
                Label(isFav ? "Remove from Favourites" : "Add to Favourites", systemImage: isFav ? "heart.slash" : "heart.fill")
            }
        }
    }
}

// MARK: - Movie / Series Centered Artwork

struct MovieArtworkView: View {
    let logoURL: URL?
    let title: String
    let isSeries: Bool
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var uiImage: UIImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .center) {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                fallbackView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private var fallbackView: some View {
        VStack(spacing: 8) {
            Image(systemName: isSeries ? "tv" : "film")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(themeManager.accent.opacity(0.75))

            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            if !Task.isCancelled {
                await MainActor.run {
                    self.uiImage = loaded
                }
            }
        }
    }
}

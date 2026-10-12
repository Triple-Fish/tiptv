//
//  FavoritesCatalogView.swift
//  tiptv
//

import SwiftUI

enum FavoriteFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case channels = "Live TV"
    case series = "Series"
    case movies = "Movies"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .channels: return "tv"
        case .series: return "tv.inset.filled"
        case .movies: return "film"
        }
    }
}

struct FavoritesCatalogView: View {
    let channels: [Channel]
    let movies: [Channel]
    let series: [Channel]
    let baseURL: String
    let username: String
    let password: String
    @Binding var searchText: String
    let onSelectChannel: (Channel) -> Void
    let onSelectMovie: (Channel) -> Void
    let onPlayEpisode: (Channel) -> Void

    @State private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedFilter: FavoriteFilter = .all
    @State private var selectedSeries: Channel?
    @State private var allFavoriteChannels: [Channel] = []
    @State private var allFavoriteSeries: [Channel] = []
    @State private var allFavoriteMovies: [Channel] = []
    @State private var filteredChannels: [Channel] = []
    @State private var filteredSeries: [Channel] = []
    @State private var filteredMovies: [Channel] = []
    @State private var filterTask: Task<Void, Never>?

    private var totalFavoritesCount: Int {
        allFavoriteChannels.count + allFavoriteSeries.count + allFavoriteMovies.count
    }

    private func count(for filter: FavoriteFilter) -> Int {
        switch filter {
        case .all:
            return totalFavoritesCount
        case .channels:
            return allFavoriteChannels.count
        case .series:
            return allFavoriteSeries.count
        case .movies:
            return allFavoriteMovies.count
        }
    }

    private func refreshFavorites() {
        filterTask?.cancel()
        let favoriteURLs = favoritesManager.favoriteStreamURLs
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentChannels = channels
        let currentSeries = series
        let currentMovies = movies

        filterTask = Task.detached(priority: .userInitiated) {
            let favoriteChannels = ChannelCatalog.favoriteChannels(in: currentChannels, favoriteStreamURLs: favoriteURLs)
            let favoriteSeries = ChannelCatalog.favoriteChannels(in: currentSeries, favoriteStreamURLs: favoriteURLs)
            let favoriteMovies = ChannelCatalog.favoriteChannels(in: currentMovies, favoriteStreamURLs: favoriteURLs)
            guard !Task.isCancelled else { return }

            let visibleChannels = ChannelCatalog.favoriteChannels(in: favoriteChannels, favoriteStreamURLs: favoriteURLs, query: query)
            let visibleSeries = ChannelCatalog.favoriteChannels(in: favoriteSeries, favoriteStreamURLs: favoriteURLs, query: query)
            let visibleMovies = ChannelCatalog.favoriteChannels(in: favoriteMovies, favoriteStreamURLs: favoriteURLs, query: query)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                allFavoriteChannels = favoriteChannels
                allFavoriteSeries = favoriteSeries
                allFavoriteMovies = favoriteMovies
                filteredChannels = visibleChannels
                filteredSeries = visibleSeries
                filteredMovies = visibleMovies
            }
        }
    }

    private let posterColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ZStack {
            tiptvTheme.contentBackground.ignoresSafeArea()

            if totalFavoritesCount == 0 {
                emptyAllFavoritesView
            } else {
                VStack(spacing: 0) {
                    // Filter Pills Bar
                    filterPillsBar
                        .padding(.vertical, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            switch selectedFilter {
                            case .all:
                                allSectionsView
                            case .channels:
                                channelsSectionView(title: "Live TV Channels (\(filteredChannels.count))", showHeader: false)
                            case .series:
                                seriesSectionView(title: "TV Series (\(filteredSeries.count))", showHeader: false)
                            case .movies:
                                moviesSectionView(title: "Movies (\(filteredMovies.count))", showHeader: false)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("Favourites")
        .searchable(text: $searchText, prompt: "Search favourites")
        .task {
            refreshFavorites()
        }
        .onChange(of: searchText) { _, _ in
            refreshFavorites()
        }
        .onChange(of: favoritesManager.favoriteStreamURLs) { _, _ in
            refreshFavorites()
        }
        .onChange(of: channels.count) { _, _ in
            refreshFavorites()
        }
        .onChange(of: series.count) { _, _ in
            refreshFavorites()
        }
        .onChange(of: movies.count) { _, _ in
            refreshFavorites()
        }
        .onDisappear {
            filterTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tiptvTheme.liveRed)
                    Text("\(totalFavoritesCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .sheet(item: $selectedSeries) { seriesItem in
            SeriesDetailView(
                series: seriesItem,
                baseURL: baseURL,
                username: username,
                password: password,
                onPlayEpisode: onPlayEpisode,
                onDismiss: { selectedSeries = nil }
            )
        }
    }

    // MARK: - Filter Pills Bar

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FavoriteFilter.allCases) { filter in
                    let isSelected = filter == selectedFilter
                    let itemCount = count(for: filter)

                    Button {
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(filter == .all ? tiptvTheme.liveRed : (isSelected ? .white : .white.opacity(0.7)))

                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.85))

                            Text("\(itemCount)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? themeManager.accent : .white.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    isSelected ? Color.black.opacity(0.3) : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? themeManager.accent.opacity(0.25) : Color.white.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? themeManager.accent.opacity(0.6) : Color.white.opacity(0.1),
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Combined Sections View (Filter == .all)

    @ViewBuilder
    private var allSectionsView: some View {
        if filteredChannels.isEmpty && filteredSeries.isEmpty && filteredMovies.isEmpty {
            noSearchResultsView
        } else {
            if !filteredChannels.isEmpty {
                channelsSectionView(title: "Live TV Channels (\(filteredChannels.count))", showHeader: true)
            }
            if !filteredSeries.isEmpty {
                seriesSectionView(title: "TV Series (\(filteredSeries.count))", showHeader: true)
            }
            if !filteredMovies.isEmpty {
                moviesSectionView(title: "Movies (\(filteredMovies.count))", showHeader: true)
            }
        }
    }

    // MARK: - Channels Section

    @ViewBuilder
    private func channelsSectionView(title: String, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showHeader {
                sectionHeader(title: title, icon: "tv")
            }

            if filteredChannels.isEmpty {
                emptyFilteredCategoryView(name: "live TV channels")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredChannels) { channel in
                        favoriteChannelRow(channel)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func favoriteChannelRow(_ channel: Channel) -> some View {
        Button {
            #if canImport(UIKit)
            Haptics.selection()
            #endif
            onSelectChannel(channel)
        } label: {
            HStack(spacing: 12) {
                // Channel Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)

                    if let logo = channel.logoURL {
                        AsyncImage(url: logo) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .scaledToFit()
                                    .padding(4)
                            default:
                                Image(systemName: "tv")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "tv")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Titles
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.uniformName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let group = channel.group, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Heart Button
                Button {
                    #if canImport(UIKit)
                    Haptics.light()
                    #endif
                    withAnimation {
                        favoritesManager.toggleFavorite(channel)
                    }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(tiptvTheme.liveRed)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from Favourites")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                #if canImport(UIKit)
                Haptics.light()
                #endif
                withAnimation {
                    favoritesManager.toggleFavorite(channel)
                }
            } label: {
                Label("Remove from Favourites", systemImage: "heart.slash")
            }
        }
    }

    // MARK: - Series Section

    @ViewBuilder
    private func seriesSectionView(title: String, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showHeader {
                sectionHeader(title: title, icon: "tv.inset.filled")
            }

            if filteredSeries.isEmpty {
                emptyFilteredCategoryView(name: "series")
            } else {
                LazyVGrid(columns: posterColumns, spacing: 14) {
                    ForEach(filteredSeries) { item in
                        MoviePosterCard(item: item) {
                            selectedSeries = item
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                #if canImport(UIKit)
                                Haptics.light()
                                #endif
                                withAnimation {
                                    favoritesManager.toggleFavorite(item)
                                }
                            } label: {
                                Label("Remove from Favourites", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Movies Section

    @ViewBuilder
    private func moviesSectionView(title: String, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showHeader {
                sectionHeader(title: title, icon: "film")
            }

            if filteredMovies.isEmpty {
                emptyFilteredCategoryView(name: "movies")
            } else {
                LazyVGrid(columns: posterColumns, spacing: 14) {
                    ForEach(filteredMovies) { item in
                        MoviePosterCard(item: item) {
                            onSelectMovie(item)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                #if canImport(UIKit)
                                Haptics.light()
                                #endif
                                withAnimation {
                                    favoritesManager.toggleFavorite(item)
                                }
                            } label: {
                                Label("Remove from Favourites", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(themeManager.accent)

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var emptyAllFavoritesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(tiptvTheme.liveRed.opacity(0.6))
                .padding(.top, 40)

            Text("No Favourites Yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Tap the heart icon on any TV channel, TV series, or movie to add it to your favourites for quick access.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyFilteredCategoryView(name: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "heart")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 20)

            Text("No favorite \(name)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            Text("Add \(name) to your favourites by tapping their heart icon.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 24)

            Text("No Favourites Found")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("No favourites match '\(searchText)'.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

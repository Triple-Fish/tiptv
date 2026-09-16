//
//  ChannelSearchView.swift
//  tiptv
//

import SwiftUI

struct ChannelSearchView: View {
    let channels: [Channel]
    let onSelectChannel: (Channel) -> Void
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var hiddenManager = HiddenChannelsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var query = ""
    @State private var selectedCategory: NetflixCategory = .all
    @FocusState private var isSearchFocused: Bool
    @State private var displayLimit = 150

    @State private var visibleChannels: [Channel] = []
    @State private var availableCategories: [NetflixCategory] = [.all]
    @State private var filteredChannels: [Channel] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    private var paginatedFilteredChannels: [Channel] {
        if filteredChannels.count <= displayLimit {
            return filteredChannels
        }
        return Array(filteredChannels.prefix(displayLimit))
    }

    private func setupData() {
        let hidden = hiddenManager.hiddenStreamURLs
        let vis = hidden.isEmpty ? channels : channels.filter { !hidden.contains($0.streamURLString) }
        visibleChannels = vis

        var categories: [NetflixCategory] = [.all]
        if !favoritesManager.favoriteStreamURLs.isEmpty {
            categories.append(.favorites)
        }
        var presentCats = Set<NetflixCategory>()
        for ch in vis {
            presentCats.insert(ch.category)
        }
        for cat in NetflixCategory.allCases where cat != .all && cat != .favorites {
            if presentCats.contains(cat) {
                categories.append(cat)
            }
        }
        availableCategories = categories
        performFilter()
    }

    private func queueSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            performFilter()
        }
    }

    private func performFilter() {
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

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Input Field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tiptvTheme.aqua)

                    TextField("Search by channel name or group...", text: $query)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()
                        .disableAutocapitalization()

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear text")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tiptvTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // Category Quick Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories) { cat in
                            let isSelected = cat == selectedCategory
                            Button {
                                Haptics.selection()
                                selectedCategory = cat
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(cat == .favorites ? tiptvTheme.liveRed : (isSelected ? .white : .white.opacity(0.7)))
                                    Text(cat.rawValue)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? themeManager.accent : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                // Results list
                List {
                    if filteredChannels.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: selectedCategory == .favorites ? "heart.slash" : "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(.top, 40)
                            Text(
                                selectedCategory == .favorites
                                    ? "No favorite channels matching this search"
                                    : (query.isEmpty ? "Start typing to search channels" : "No channels found for “\(query)”")
                            )
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(paginatedFilteredChannels) { channel in
                                Button {
                                    onSelectChannel(channel)
                                    dismiss()
                                } label: {
                                    ChannelRow(
                                    channel: channel,
                                    isSelected: false,
                                    isFavorite: favoritesManager.isFavorite(channel)
                                )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Haptics.medium()
                                        withAnimation {
                                            hiddenManager.hideChannel(channel)
                                        }
                                    } label: {
                                        Label("Hide Channel", systemImage: "eye.slash")
                                    }

                                    Button {
                                        Haptics.light()
                                        withAnimation {
                                            favoritesManager.toggleFavorite(channel)
                                        }
                                    } label: {
                                        Label(
                                            favoritesManager.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites",
                                            systemImage: favoritesManager.isFavorite(channel) ? "heart.slash" : "heart"
                                        )
                                    }
                                }
                            }

                            if filteredChannels.count > displayLimit {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(themeManager.accent)
                                        .padding(.vertical, 8)
                                        .onAppear {
                                            displayLimit = min(displayLimit + 150, filteredChannels.count)
                                        }
                                    Spacer()
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text("\(filteredChannels.count) \(filteredChannels.count == 1 ? "RESULT" : "RESULTS")")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(0.6)
                                    .foregroundStyle(.white.opacity(0.4))
                                Spacer()
                            }
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(tiptvTheme.contentBackground.ignoresSafeArea())
            .navigationTitle("Search")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(tiptvTheme.aqua)
                }
            }
            .onAppear {
                isSearchFocused = true
                setupData()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .tint(tiptvTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: query) { _, _ in
            displayLimit = 150
            queueSearch()
        }
        .onChange(of: selectedCategory) { _, _ in
            displayLimit = 150
            performFilter()
        }
        .onReceive(favoritesManager.$favoriteStreamURLs) { _ in
            setupData()
        }
        .onReceive(hiddenManager.$hiddenStreamURLs) { _ in
            setupData()
        }
    }
}

import SwiftUI

// MARK: - Custom Bottom Tab Bar

struct BottomTabBar: View {
  @Binding var selectedTab: AppTab
  let onSelectTab: (AppTab) -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(AppTab.allCases) { tab in
        let isSelected = tab == selectedTab
        Button {
          Haptics.selection()
          onSelectTab(tab)
        } label: {
          VStack(spacing: 4) {
            Image(systemName: tab.icon)
              .font(.system(size: 18, weight: isSelected ? .bold : .regular))
              .foregroundStyle(isSelected ? TipTVTheme.accent : .white.opacity(0.42))

            Text(tab.rawValue)
              .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
              .foregroundStyle(isSelected ? TipTVTheme.accent : .white.opacity(0.45))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 9)
          .background(
            isSelected ? TipTVTheme.accent.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
          )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(5)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(.ultraThinMaterial)
        Color.black.opacity(0.7)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    )
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
  }
}

// MARK: - Channel Library View

struct ChannelLibraryView: View {
  let channels: [Channel]
  let totalChannelCount: Int
  let categories: [ChannelCategory]
  let categoryCounts: [ChannelCategory: Int]
  @Binding var selectedCategory: ChannelCategory
  @Binding var selectedChannelID: Channel.ID?
  let isLoading: Bool
  let onSelectChannel: (Channel) -> Void
  let openPlaylistImporter: () -> Void
  let reloadPlaylist: () -> Void
  let deletePlaylist: () -> Void

  @State private var favoritesManager = FavoritesManager.shared
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingTimelineGuide = false
  @State private var displayLimit = 250

  private var paginatedChannels: [Channel] {
    if channels.count <= displayLimit {
      return channels
    }
    return Array(channels.prefix(displayLimit))
  }

  var body: some View {
    VStack(spacing: 0) {
      ChannelLibraryDashboard(totalChannelCount: totalChannelCount)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)

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
              ContentUnavailableView(
                "No Channels in This Category",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Choose another category to see more channels.")
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
                    systemImage: favoritesManager.isFavorite(channel)
                      ? "heart.slash.fill" : "heart.fill"
                  )
                }
                .tint(favoritesManager.isFavorite(channel) ? .gray : TipTVTheme.liveRed)
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
                    FavoritesManager.shared.isFavorite(channel)
                      ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: FavoritesManager.shared.isFavorite(channel)
                      ? "heart.slash" : "heart"
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
                  .tint(TipTVTheme.accent)
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
            isFiltered: selectedCategory != .all,
            categoryTitle: selectedCategory.rawValue
          )
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
    .background(TipTVTheme.contentBackground.ignoresSafeArea())
    .navigationTitle("TV Guide")
    .onChange(of: selectedCategory) {
      displayLimit = 250
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if totalChannelCount > 0 {
          Button {
            isShowingTimelineGuide = true
          } label: {
            Image(systemName: "calendar.day.timeline.leading")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(TipTVTheme.accent)
              .frame(width: 32, height: 32)
              .background(TipTVTheme.accent.opacity(0.12), in: Circle())
          }
          .accessibilityLabel("Open Timeline Guide")
        }

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
    .sheet(isPresented: $isShowingTimelineGuide) {
      NavigationStack {
        TimelineGuideView(
          channels: channels,
          onSelectChannel: { channel in
            isShowingTimelineGuide = false
            onSelectChannel(channel)
          }
        )
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              isShowingTimelineGuide = false
            }
          }
        }
      }
      .preferredColorScheme(.dark)
    }
  }
}

private struct ChannelLibraryDashboard: View {
  let totalChannelCount: Int

  var body: some View {
    HStack(spacing: 14) {
      TipTVBrandLogo(size: 24)
        .accessibilityLabel("Tiptv")

      VStack(alignment: .leading, spacing: 2) {
        Text("Your TV, all in one place")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Text(
          totalChannelCount == 0
            ? "Add a playlist to get started" : "\(totalChannelCount.formatted()) channels ready"
        )
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.58))
      }

      Spacer()

      if totalChannelCount > 0 {
        Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(TipTVTheme.liveRed)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .background(TipTVTheme.liveRed.opacity(0.12), in: Capsule())
      }
    }
    .padding(14)
    .background(
      TipTVTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(TipTVTheme.cardBorder, lineWidth: 0.5)
    }
  }
}

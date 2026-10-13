import AVFoundation
import AVKit
import ImageIO
import SwiftUI

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
                .fill(isUsingKSPlayer ? TipTVTheme.accent : TipTVTheme.aqua)
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
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(TipTVTheme.accent.opacity(0.2), in: Circle())
          .overlay(Circle().strokeBorder(TipTVTheme.accent.opacity(0.4), lineWidth: 0.75))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPlaying ? "Pause" : "Play")

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.white.opacity(0.72))
          .frame(width: 36, height: 36)
          .background(Color.white.opacity(0.08), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop Playback")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(TipTVTheme.accent.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: TipTVTheme.accent.opacity(0.22), radius: 14, y: 5)
    )
  }
}

// MARK: - Netflix-Style Category Pills Bar

struct CategoryPillsBar: View {
  let categories: [ChannelCategory]
  let categoryCounts: [ChannelCategory: Int]
  @Binding var selectedCategory: ChannelCategory
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
                  .foregroundStyle(
                    category == .favorites
                      ? TipTVTheme.liveRed : (isSelected ? .white : .white.opacity(0.65)))

                Text(category.rawValue)
                  .font(
                    .system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded)
                  )
                  .foregroundStyle(isSelected ? .white : .white.opacity(0.68))

                if let count = categoryCounts[category] {
                  Text("\(count)")
                    .font(
                      .system(size: 10, weight: isSelected ? .bold : .semibold, design: .rounded)
                    )
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
                    .fill(
                      category == .favorites
                        ? AnyShapeStyle(Color.red.opacity(0.6))
                        : AnyShapeStyle(TipTVTheme.artworkGradient)
                    )
                    .matchedGeometryEffect(id: "activeCategoryPill", in: pillNamespace)
                    .shadow(
                      color: (category == .favorites ? Color.red : TipTVTheme.accent).opacity(0.38),
                      radius: 8, y: 2)
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
        .foregroundStyle(.white.opacity(0.56))

      Spacer()

      Text("\(displayedCount) \(displayedCount == 1 ? "channel" : "channels")")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(Color.white.opacity(0.06), in: Capsule())
        .foregroundStyle(.white.opacity(0.65))
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
              .foregroundStyle(TipTVTheme.liveRed)
          }
        }

        if isSelected {
          HStack(spacing: 4) {
            Circle()
              .fill(TipTVTheme.aqua)
              .frame(width: 4, height: 4)

            Text("Playing")
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .foregroundStyle(TipTVTheme.aqua)
          }
        } else if let group = channel.group, !group.isEmpty {
          Text(group)
            .lineLimit(1)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
        } else {
          Text("Live TV")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
        }
      }

      Spacer(minLength: 8)

      if isSelected {
        Image(systemName: "waveform")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(TipTVTheme.aqua)
      } else {
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.38))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isSelected ? TipTVTheme.accent.opacity(0.2) : TipTVTheme.cardBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
              isSelected ? TipTVTheme.accent.opacity(0.65) : TipTVTheme.cardBorder,
              lineWidth: 1
            )
        }
        .shadow(
          color: isSelected ? TipTVTheme.accent.opacity(0.25) : .clear,
          radius: 8,
          y: 3
        )
    }
    .overlay(alignment: .leading) {
      if isSelected {
        Capsule()
          .fill(TipTVTheme.artworkGradient)
          .frame(width: 3, height: 34)
          .padding(.leading, 2)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityHint(isSelected ? "Currently playing" : "Plays this channel")
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
      TipTVTheme.artworkGradient

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
        .fill(TipTVTheme.cardBackground)
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
          .fill(TipTVTheme.liveRed.opacity(0.18))
          .frame(width: 56, height: 56)

        Image(systemName: "heart.slash")
          .font(.system(size: 24, weight: .regular))
          .foregroundStyle(TipTVTheme.liveRed)
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
        .background(TipTVTheme.artworkGradient, in: Capsule())
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity)
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 20)
        .fill(TipTVTheme.cardBackground)
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
        .shadow(color: TipTVTheme.accent.opacity(0.35), radius: 10, y: 3)

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
        .background(TipTVTheme.artworkGradient, in: Capsule())
        .shadow(color: TipTVTheme.accent.opacity(0.35), radius: 10, y: 4)
      }
      .buttonStyle(.plain)
      .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity)
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 20)
        .fill(TipTVTheme.cardBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 20)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    )
  }
}

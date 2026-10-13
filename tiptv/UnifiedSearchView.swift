import Observation
import SwiftUI

nonisolated private enum UnifiedSearchKind: String, Sendable {
  case live = "Live TV"
  case programme = "Programmes"
  case movie = "Movies"
  case series = "Series & Episodes"

  var icon: String {
    switch self {
    case .live: "tv"
    case .programme: "calendar"
    case .movie: "film"
    case .series: "tv.inset.filled"
    }
  }
}

nonisolated private struct UnifiedSearchResult: Identifiable, Sendable {
  let id: String
  let kind: UnifiedSearchKind
  let title: String
  let subtitle: String
  let channel: Channel
}

@MainActor
@Observable
private final class UnifiedSearchModel {
  private(set) var liveResults: [UnifiedSearchResult] = []
  private(set) var programmeResults: [UnifiedSearchResult] = []
  private(set) var movieResults: [UnifiedSearchResult] = []
  private(set) var seriesResults: [UnifiedSearchResult] = []
  private(set) var isSearching = false

  var isEmpty: Bool {
    liveResults.isEmpty && programmeResults.isEmpty && movieResults.isEmpty && seriesResults.isEmpty
  }

  func search(
    query: String, channels: [Channel], movies: [Channel], series: [Channel],
    programs: [UUID: [EPGProgram]]
  ) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      liveResults = []
      programmeResults = []
      movieResults = []
      seriesResults = []
      isSearching = false
      return
    }

    isSearching = true
    do {
      try await Task.sleep(for: .milliseconds(250))
    } catch {
      return
    }

    let work = Task.detached(priority: .userInitiated) {
      Self.performSearch(
        query: trimmed, channels: channels, movies: movies, series: series, programs: programs)
    }
    guard
      let result = await withTaskCancellationHandler(
        operation: {
          await work.value
        },
        onCancel: {
          work.cancel()
        })
    else { return }

    guard !Task.isCancelled else { return }
    liveResults = result.0
    programmeResults = result.1
    movieResults = result.2
    seriesResults = result.3
    isSearching = false
  }

  nonisolated private static func performSearch(
    query: String,
    channels: [Channel],
    movies: [Channel],
    series: [Channel],
    programs: [UUID: [EPGProgram]]
  ) -> ([UnifiedSearchResult], [UnifiedSearchResult], [UnifiedSearchResult], [UnifiedSearchResult])?
  {
    let normalizedQuery = query.lowercased()
    guard
      let live = channelResults(
        in: channels, query: normalizedQuery, kind: .live, fallbackSubtitle: "Live TV",
        liveOnly: true),
      let movieMatches = channelResults(
        in: movies, query: normalizedQuery, kind: .movie, fallbackSubtitle: "Movie"),
      let seriesMatches = channelResults(
        in: series, query: normalizedQuery, kind: .series, fallbackSubtitle: "Series")
    else {
      return nil
    }

    let channelsByID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
    var programmeMatches: [UnifiedSearchResult] = []
    for (channelID, channelPrograms) in programs {
      if Task.isCancelled { return nil }
      if programmeMatches.count >= 60 { break }
      guard let channel = channelsByID[channelID] else { continue }
      for programme in channelPrograms where programmeMatches.count < 60 {
        if programme.title.localizedCaseInsensitiveContains(query)
          || programme.subtitle?.localizedCaseInsensitiveContains(query) == true
          || programme.synopsis.localizedCaseInsensitiveContains(query)
        {
          programmeMatches.append(
            UnifiedSearchResult(
              id: "programme-\(programme.id)",
              kind: .programme,
              title: programme.title,
              subtitle: "\(channel.uniformName) · \(programme.timeRangeString)",
              channel: channel
            ))
        }
      }
    }
    programmeMatches.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    return (live, programmeMatches, movieMatches, seriesMatches)
  }

  nonisolated private static func channelResults(
    in channels: [Channel],
    query: String,
    kind: UnifiedSearchKind,
    fallbackSubtitle: String,
    liveOnly: Bool = false
  ) -> [UnifiedSearchResult]? {
    var results: [UnifiedSearchResult] = []
    results.reserveCapacity(60)
    for (index, channel) in channels.enumerated() {
      if index.isMultiple(of: 1_000), Task.isCancelled { return nil }
      if liveOnly && channel.isVOD { continue }
      guard matches(channel, query: query) else { continue }
      results.append(
        UnifiedSearchResult(
          id: "\(kind.rawValue)-\(channel.id)",
          kind: kind,
          title: channel.uniformName,
          subtitle: channel.group ?? fallbackSubtitle,
          channel: channel
        ))
      if results.count == 60 { break }
    }
    return results
  }

  nonisolated private static func matches(_ channel: Channel, query: String) -> Bool {
    channel.searchKey.contains(query)
  }
}

struct UnifiedSearchView: View {
  let channels: [Channel]
  let movies: [Channel]
  let series: [Channel]
  let onSelect: (Channel) -> Void
  @State private var model = UnifiedSearchModel()
  @State private var query = ""
  @State private var epgManager = EPGManager.shared

  var body: some View {
    NavigationStack {
      List {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
          ContentUnavailableView(
            "Search Everything",
            systemImage: "magnifyingglass",
            description: Text(
              "Find live channels, programmes, movies, series and playlist episodes.")
          )
        } else if model.isSearching {
          HStack {
            Spacer()
            ProgressView("Searching…")
            Spacer()
          }
        } else if model.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          UnifiedSearchSection(title: "Live TV", results: model.liveResults, onSelect: onSelect)
          UnifiedSearchSection(
            title: "Programmes", results: model.programmeResults, onSelect: onSelect)
          UnifiedSearchSection(title: "Movies", results: model.movieResults, onSelect: onSelect)
          UnifiedSearchSection(
            title: "Series & Episodes", results: model.seriesResults, onSelect: onSelect)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(TipTVTheme.contentBackground.ignoresSafeArea())
      .navigationTitle("Search")
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Channels, shows, movies and series"
      )
      .task(id: query) {
        await model.search(
          query: query,
          channels: channels,
          movies: movies,
          series: series,
          programs: epgManager.programsByChannelID
        )
      }
    }
  }
}

private struct UnifiedSearchSection: View {
  let title: String
  let results: [UnifiedSearchResult]
  let onSelect: (Channel) -> Void

  var body: some View {
    if !results.isEmpty {
      Section {
        ForEach(results) { result in
          Button {
            onSelect(result.channel)
          } label: {
            UnifiedSearchRow(
              title: result.title,
              subtitle: result.subtitle,
              icon: result.kind.icon
            )
          }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
      } header: {
        Text(title.uppercased())
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .tracking(0.8)
          .foregroundStyle(.white.opacity(0.56))
          .textCase(nil)
      }
    }
  }
}

private struct UnifiedSearchRow: View {
  let title: String
  let subtitle: String
  let icon: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(TipTVTheme.aqua)
        .frame(width: 36, height: 36)
        .background(TipTVTheme.aqua.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundStyle(.white)
          .lineLimit(1)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.32))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(TipTVTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(TipTVTheme.cardBorder, lineWidth: 0.75)
    }
  }
}

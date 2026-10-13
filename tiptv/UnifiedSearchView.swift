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

    func search(query: String, channels: [Channel], movies: [Channel], series: [Channel], programs: [UUID: [EPGProgram]]) async {
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

        let result = await Task.detached(priority: .userInitiated) {
            Self.performSearch(query: trimmed, channels: channels, movies: movies, series: series, programs: programs)
        }.value

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
    ) -> ([UnifiedSearchResult], [UnifiedSearchResult], [UnifiedSearchResult], [UnifiedSearchResult]) {
            let live = channels.lazy
                .filter { !$0.isVOD && Self.matches($0, query: query) }
                .prefix(60)
                .map { UnifiedSearchResult(id: "live-\($0.id)", kind: .live, title: $0.uniformName, subtitle: $0.group ?? "Live TV", channel: $0) }
            let movieMatches = movies.lazy
                .filter { Self.matches($0, query: query) }
                .prefix(60)
                .map { UnifiedSearchResult(id: "movie-\($0.id)", kind: .movie, title: $0.uniformName, subtitle: $0.group ?? "Movie", channel: $0) }
            let seriesMatches = series.lazy
                .filter { Self.matches($0, query: query) }
                .prefix(60)
                .map { UnifiedSearchResult(id: "series-\($0.id)", kind: .series, title: $0.uniformName, subtitle: $0.group ?? "Series", channel: $0) }

            let channelsByID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
            var programmeMatches: [UnifiedSearchResult] = []
            for (channelID, channelPrograms) in programs {
                guard let channel = channelsByID[channelID] else { continue }
                for programme in channelPrograms where programmeMatches.count < 60 {
                    if programme.title.localizedCaseInsensitiveContains(query)
                        || programme.subtitle?.localizedCaseInsensitiveContains(query) == true
                        || programme.synopsis.localizedCaseInsensitiveContains(query) {
                        programmeMatches.append(UnifiedSearchResult(
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
            return (Array(live), programmeMatches, Array(movieMatches), Array(seriesMatches))
    }

    nonisolated private static func matches(_ channel: Channel, query: String) -> Bool {
        channel.uniformName.localizedCaseInsensitiveContains(query)
            || channel.name.localizedCaseInsensitiveContains(query)
            || channel.group?.localizedCaseInsensitiveContains(query) == true
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
                        description: Text("Find live channels, programmes, movies, series and playlist episodes.")
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
                    UnifiedSearchSection(title: "Programmes", results: model.programmeResults, onSelect: onSelect)
                    UnifiedSearchSection(title: "Movies", results: model.movieResults, onSelect: onSelect)
                    UnifiedSearchSection(title: "Series & Episodes", results: model.seriesResults, onSelect: onSelect)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channels, shows, movies and series")
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
            Section(title) {
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
                }
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
                .foregroundStyle(tiptvTheme.aqua)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

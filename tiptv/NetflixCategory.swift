//
//  NetflixCategory.swift
//  tiptv
//

import Foundation

enum NetflixCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case favorites = "Favorites"
    case sports = "Sports"
    case movies = "Movies"
    case series = "Series"
    case entertainment = "Entertainment"
    case news = "News"
    case documentaries = "Documentaries"
    case kids = "Kids & Family"
    case music = "Music"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .favorites: return "heart.fill"
        case .sports: return "sportscourt"
        case .movies: return "film"
        case .series: return "tv.inset.filled"
        case .entertainment: return "tv"
        case .news: return "newspaper"
        case .documentaries: return "globe.americas"
        case .kids: return "face.smiling"
        case .music: return "music.note"
        case .other: return "square.grid.2x2"
        }
    }

    // Pre-allocated static keyword lists for fast classification without per-channel array allocations
    nonisolated private static let sportsKeywords: [String] = [
        "sport", "football", "soccer", "nba", "nfl", "nhl", "mlb", "espn", "racing", "f1",
        "formula 1", "formula1", "tennis", "golf", "cricket", "rugby", "ufc", "fight",
        "boxing", "wwe", "ppv", "bein", "dazn", "sky sport", "tnt sport", "super sport",
        "atp", "wta", "motogp", "nascar", "athletics", "pga", "mls", "premier league", "laliga"
    ]

    nonisolated private static let movieKeywords: [String] = [
        "movie", "cinema", "film", "films", "hbo", "cine", "box office", "vod", "premiere",
        "action", "comedy", "thriller", "horror", "drama", "sci-fi", "hallmark",
        "cinemax", "showtime", "starz", "paramount+", "blockbuster",
        "kino", "pelicula", "filme", "western", "crime", "adventure", "romance",
        "fantasy", "mystery", "war", "bluray", "web-dl", "remux", "4k uhd"
    ]

    nonisolated private static let newsKeywords: [String] = [
        "news", "weather", "cnn", "bbc news", "sky news", "msnbc", "fox news",
        "bloomberg", "cnbc", "c-span", "al jazeera", "euronews", "headline", "info"
    ]

    nonisolated private static let kidsKeywords: [String] = [
        "kid", "children", "cartoon", "animation", "disney", "nick", "nickelodeon",
        "cbbc", "cbeebies", "junior", "family", "boomerang", "baby", "toon"
    ]

    nonisolated private static let docKeywords: [String] = [
        "documentary", "documentaries", "discovery", "nat geo", "national geographic",
        "history", "investigation", "science", "nature", "animal planet", "crime",
        "smithsonian", "curiosity", "wild", "planet"
    ]

    nonisolated private static let musicKeywords: [String] = [
        "music", "mtv", "vh1", "radio", "song", "concert", "hit", "vevo", "soundtrack", "clubland"
    ]

    nonisolated private static let seriesKeywords: [String] = [
        "series", "season", "boxset", "episodes", "tv shows", "tv series", "tv show"
    ]

    nonisolated private static let entertainmentKeywords: [String] = [
        "entertainment", "general", "show", "variety", "reality",
        "lifestyle", "food", "cooking", "travel", "fashion", "home", "hgtv",
        "tlc", "bravo", "e!", "comedy central", "drama", "itv", "bbc", "channel 4",
        "c4", "channel 5", "c5", "sky max", "sky showcase", "sky atlantic"
    ]

/// Intelligently classifies any channel into a high level content category
    /// based on its playlist group and channel title.
    nonisolated static func classify(group: String?, name: String) -> NetflixCategory {
        let combined = "\(group ?? "") \(name)".lowercased()

        // 1. Sports
        if sportsKeywords.contains(where: { combined.contains($0) }) {
            return .sports
        }

        // 2. Series & TV Shows
        if seriesKeywords.contains(where: { combined.contains($0) }) {
            return .series
        }
        if let regex = try? NSRegularExpression(pattern: #"\b[sS]\d{1,2}\s*[eE]\d{1,2}\b|\bseason\s*\d+\b"#) {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                return .series
            }
        }

        // 3. Movies & Cinema
        if movieKeywords.contains(where: { combined.contains($0) }) {
            return .movies
        }

        // 4. News
        if newsKeywords.contains(where: { combined.contains($0) }) {
            return .news
        }

        // 5. Kids & Family
        if kidsKeywords.contains(where: { combined.contains($0) }) {
            return .kids
        }

        // 6. Documentaries & Nature
        if docKeywords.contains(where: { combined.contains($0) }) {
            return .documentaries
        }

        // 7. Music
        if musicKeywords.contains(where: { combined.contains($0) }) {
            return .music
        }

        // 8. Entertainment
        if entertainmentKeywords.contains(where: { combined.contains($0) }) {
            return .entertainment
        }

        return .other
    }
}

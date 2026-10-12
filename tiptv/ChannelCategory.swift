//
//  ChannelCategory.swift
//  tiptv
//

import Foundation

enum ChannelCategory: String, CaseIterable, Identifiable, Sendable, Codable {
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

    nonisolated private static let seriesClassifierRegex = try? NSRegularExpression(pattern: #"\\b[sS]\d{1,2}\s*[eE]\d{1,2}\b|\bseason\s*\d+\b"#)

    // Memoized cache for playlist group classifications (typically 30-100 unique groups across 50,000 channels)
    nonisolated(unsafe) private static let groupClassificationCache = NSCache<NSString, NSString>()

    /// Intelligently classifies any channel into a high level content category
    /// based on its playlist group and channel title with ultra-fast group memoization.
    nonisolated static func classify(group: String?, name: String) -> ChannelCategory {
        // 1. Check if group alone uniquely identifies the category (95%+ of IPTV channels)
        if let group, !group.isEmpty {
            let nsGroup = group as NSString
            if let cached = groupClassificationCache.object(forKey: nsGroup) {
                if let cat = ChannelCategory(rawValue: cached as String) {
                    return cat
                }
            }

            let gLower = group.lowercased()
            let matchedCategory: ChannelCategory? = {
                if sportsKeywords.contains(where: { gLower.contains($0) }) { return .sports }
                if seriesKeywords.contains(where: { gLower.contains($0) }) { return .series }
                if movieKeywords.contains(where: { gLower.contains($0) }) { return .movies }
                if newsKeywords.contains(where: { gLower.contains($0) }) { return .news }
                if kidsKeywords.contains(where: { gLower.contains($0) }) { return .kids }
                if docKeywords.contains(where: { gLower.contains($0) }) { return .documentaries }
                if musicKeywords.contains(where: { gLower.contains($0) }) { return .music }
                if entertainmentKeywords.contains(where: { gLower.contains($0) }) { return .entertainment }
                return nil
            }()

            if let matched = matchedCategory {
                groupClassificationCache.setObject(matched.rawValue as NSString, forKey: nsGroup)
                return matched
            }
        }

        // 2. Fallback to combined group + channel title inspection
        let combined = "\(group ?? "") \(name)".lowercased()

        if sportsKeywords.contains(where: { combined.contains($0) }) {
            return .sports
        }

        if seriesKeywords.contains(where: { combined.contains($0) }) {
            return .series
        }
        if let regex = seriesClassifierRegex {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                return .series
            }
        }

        if movieKeywords.contains(where: { combined.contains($0) }) {
            return .movies
        }

        if newsKeywords.contains(where: { combined.contains($0) }) {
            return .news
        }

        if kidsKeywords.contains(where: { combined.contains($0) }) {
            return .kids
        }

        if docKeywords.contains(where: { combined.contains($0) }) {
            return .documentaries
        }

        if musicKeywords.contains(where: { combined.contains($0) }) {
            return .music
        }

        if entertainmentKeywords.contains(where: { combined.contains($0) }) {
            return .entertainment
        }

        return .other
    }
}

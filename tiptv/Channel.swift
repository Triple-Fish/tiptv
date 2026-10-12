import CryptoKit
import Foundation

// MARK: - Models & Helpers

struct Channel: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let name: String
    let tvgID: String?
    let uniformName: String
    let group: String?
    let logoURL: URL?
    let streamURL: URL
    let streamURLString: String
    let category: ChannelCategory
    let searchKey: String
    let isMovie: Bool
    let isSeries: Bool

    nonisolated var isVOD: Bool {
        isMovie || isSeries
    }

    nonisolated private static let movieYearRegex = try? NSRegularExpression(pattern: #"[\(\[]\s*(19\d{2}|20\d{2})\s*[\)\]]"#)
    nonisolated private static let seriesRegex = try? NSRegularExpression(pattern: #"\b[sS]\d{1,2}\s*[eE]\d{1,2}\b"#)

    nonisolated private static let movieGroupKeywords: [String] = [
        "movie", "vod", "cinema", "film", "films", "kino", "pelicula", "filme",
        "action", "comedy", "thriller", "horror", "drama", "sci-fi",
        "romance", "adventure", "crime", "family", "animation",
        "western", "war", "fantasy", "mystery", "hollywood", "box office",
        "disney", "prime", "amazon", "apple tv", "hbo", "paramount",
        "starz", "cinemax", "showtime", "bluray", "web-dl", "remux", "4k uhd",
        "new releases", "top picks", "trending"
    ]

    nonisolated private static let vodExtensions: [String] = [
        ".mp4", ".mkv", ".avi", ".m4v", ".mov", ".webm", ".wmv", ".flv"
    ]

    nonisolated init(
        id: UUID? = nil,
        name: String,
        tvgID: String? = nil,
        uniformName: String? = nil,
        group: String? = nil,
        logoURL: URL? = nil,
        streamURL: URL,
        streamURLString: String? = nil,
        category: ChannelCategory? = nil,
        isMovie: Bool? = nil,
        isSeries: Bool? = nil
    ) {
        self.id = id ?? Self.stableID(for: streamURLString ?? streamURL.absoluteString)
        self.name = name
        self.tvgID = tvgID
        self.group = group
        self.logoURL = logoURL
        self.streamURL = streamURL
        let resolvedURLString = streamURLString ?? streamURL.absoluteString
        self.streamURLString = resolvedURLString
        let resolvedUniformName = uniformName ?? PlaylistParser.uniformChannelName(name)
        self.uniformName = resolvedUniformName
        let resolvedCat = category ?? ChannelCategory.classify(group: group, name: name)
        self.category = resolvedCat
        if name == resolvedUniformName {
            self.searchKey = "\(name) \(group ?? "")".lowercased()
        } else {
            self.searchKey = "\(name) \(resolvedUniformName) \(group ?? "")".lowercased()
        }

        if let isMovie {
            self.isMovie = isMovie
            self.isSeries = isSeries ?? false
        } else if let isSeries {
            self.isMovie = isMovie ?? false
            self.isSeries = isSeries
        } else if resolvedCat == .movies {
            self.isMovie = true
            self.isSeries = false
        } else if resolvedCat == .series {
            self.isMovie = false
            self.isSeries = true
        } else {
            let lowerURL = resolvedURLString.lowercased()
            let groupLower = group?.lowercased() ?? ""
            let nameLower = name.lowercased()
            let movie = Channel.computeIsMovie(
                category: resolvedCat,
                lowerURL: lowerURL,
                groupLower: groupLower,
                name: name,
                nameLower: nameLower
            )
            self.isMovie = movie
            self.isSeries = movie ? false : Channel.computeIsSeries(
                category: resolvedCat,
                lowerURL: lowerURL,
                groupLower: groupLower,
                name: name,
                nameLower: nameLower
            )
        }
    }

    nonisolated static func stableID(for streamURLString: String) -> UUID {
        let digest = SHA256.hash(data: Data(streamURLString.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    nonisolated static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated private static func computeIsMovie(
        category: ChannelCategory,
        lowerURL: String,
        groupLower: String,
        name: String,
        nameLower: String
    ) -> Bool {
        if category == .movies { return true }
        if lowerURL.contains("/movie/") || lowerURL.contains("/movies/") || lowerURL.contains("/vod/") || lowerURL.contains("/vods/") {
            return true
        }
        if lowerURL.contains("/series/") { return false }
        if groupLower.contains("series") || groupLower.contains("season") || groupLower.contains("boxset") || groupLower.contains("episodes") {
            return false
        }
        if nameLower.contains("s01") || nameLower.contains("s02") || nameLower.contains("s03") || nameLower.contains("e01") || nameLower.contains("e02") {
            return false
        }

        if movieGroupKeywords.contains(where: { groupLower.contains($0) }) && !groupLower.contains("live") && !groupLower.contains("sport") && !groupLower.contains("news") {
            return true
        }

        let hasVODExtension = vodExtensions.contains(where: { lowerURL.contains($0) })
        if hasVODExtension && !groupLower.contains("live") && !groupLower.contains("channel") && !groupLower.contains("sport") && !groupLower.contains("news") {
            return true
        }

        if let regex = movieYearRegex {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                if !groupLower.contains("live") && !groupLower.contains("sport") && !groupLower.contains("news") && !groupLower.contains("channel") {
                    return true
                }
            }
        }

        return false
    }

    nonisolated private static func computeIsSeries(
        category: ChannelCategory,
        lowerURL: String,
        groupLower: String,
        name: String,
        nameLower: String
    ) -> Bool {
        if category == .series { return true }
        if lowerURL.contains("/series/") { return true }
        if groupLower.contains("series") || groupLower.contains("season") || groupLower.contains("boxset") || groupLower.contains("tv shows") || groupLower.contains("tv series") {
            return true
        }
        if nameLower.contains("s01") || nameLower.contains("s02") || nameLower.contains("s03") || nameLower.contains("e01") || nameLower.contains("e02") || nameLower.contains("season ") || nameLower.contains("episode ") {
            return true
        }
        if let regex = seriesRegex {
            let range = NSRange(name.startIndex..., in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                return true
            }
        }
        return false
    }
}

//
//  XtreamService.swift
//  tiptv
//

import Foundation

enum XtreamService {
    static let defaultUserAgent = "IPTVSmartersPro/1.0.0"

    /// Checks if a given URL and credentials correspond to an Xtream Codes server
    static func isXtreamServer(baseURL: String, username: String, password: String) async -> Bool {
        guard !username.isEmpty, !password.isEmpty else { return false }
        let cleanBase = cleanBaseURL(baseURL)
        guard let url = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userInfo = json["user_info"] as? [String: Any],
               let auth = userInfo["auth"] as? Int, auth == 1 {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    /// Fetches all live channels from an Xtream Codes server
    static func fetchXtreamChannels(baseURL: String, username: String, password: String) async throws -> [Channel] {
        let cleanBase = cleanBaseURL(baseURL)

        // 1. Fetch categories
        var categoryMap: [String: String] = [:]
        if let catURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_live_categories") {
            var catRequest = URLRequest(url: catURL)
            catRequest.timeoutInterval = 15
            catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

            if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
               let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
                for item in catList {
                    let catID = String(describing: item["category_id"] ?? "")
                    let catName = item["category_name"] as? String ?? "General"
                    categoryMap[catID] = catName
                }
            }
        }

        // 2. Fetch live streams
        guard let streamsURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_live_streams") else {
            throw PlaylistError.unavailable
        }

        var streamRequest = URLRequest(url: streamsURL)
        streamRequest.timeoutInterval = 30
        streamRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        let (streamData, response) = try await URLSession.shared.data(for: streamRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaylistError.unavailable
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PlaylistError.unauthorized
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw PlaylistError.unavailable
        }

        return try await Task.detached(priority: .userInitiated) {
            guard let streamList = try? JSONSerialization.jsonObject(with: streamData) as? [[String: Any]] else {
                throw PlaylistError.unavailable
            }

            var channels: [Channel] = []
            channels.reserveCapacity(streamList.count)

            for dict in streamList {
                let streamID: String
                if let idInt = dict["stream_id"] as? Int {
                    streamID = String(idInt)
                } else if let idStr = dict["stream_id"] as? String, !idStr.isEmpty {
                    streamID = idStr
                } else {
                    continue
                }

                let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Channel \(streamID)"
                let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
                let finalName = trimmedName.isEmpty ? name : trimmedName

                let iconURLString = dict["stream_icon"] as? String
                let logoURL = iconURLString.flatMap { URL(string: $0) }

                let catID = String(describing: dict["category_id"] ?? "")
                let groupName = categoryMap[catID] ?? "Live TV"

                let streamURLString = "\(cleanBase)/live/\(username)/\(password)/\(streamID).m3u8"
                guard let streamURL = URL(string: streamURLString) else {
                    continue
                }

                let channel = Channel(
                    id: UUID(),
                    name: finalName,
                    group: groupName,
                    logoURL: logoURL,
                    streamURL: streamURL,
                    streamURLString: streamURLString
                )
                channels.append(channel)
            }

            guard !channels.isEmpty else {
                throw PlaylistError.noChannels
            }

            return channels
        }.value
    }


    /// Fetches all on-demand movies (VOD) from an Xtream Codes server
    static func fetchXtreamVOD(baseURL: String, username: String, password: String) async -> [Channel] {
        guard !username.isEmpty, !password.isEmpty else { return [] }
        let cleanBase = cleanBaseURL(baseURL)

        // 1. Fetch VOD categories
        var categoryMap: [String: String] = [:]
        if let catURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_vod_categories") {
            var catRequest = URLRequest(url: catURL)
            catRequest.timeoutInterval = 15
            catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

            if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
               let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
                for item in catList {
                    let catID = String(describing: item["category_id"] ?? "")
                    let catName = item["category_name"] as? String ?? "Movies"
                    categoryMap[catID] = catName
                }
            }
        }

        // 2. Fetch VOD streams via download to file (Zero-RAM spike)
        guard let streamsURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_vod_streams") else {
            return []
        }

        var streamRequest = URLRequest(url: streamsURL)
        streamRequest.timeoutInterval = 45
        streamRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (tempFileURL, response) = try? await URLSession.shared.download(for: streamRequest),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        return await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let inputStream = InputStream(url: tempFileURL) else { return [] }
                inputStream.open()
                defer { inputStream.close() }

                guard let streamList = try? JSONSerialization.jsonObject(with: inputStream) as? [[String: Any]] else {
                    return []
                }

                var movies: [Channel] = []
                movies.reserveCapacity(streamList.count)

                for dict in streamList {
                    let streamID: String
                    if let idInt = dict["stream_id"] as? Int {
                        streamID = String(idInt)
                    } else if let idStr = dict["stream_id"] as? String, !idStr.isEmpty {
                        streamID = idStr
                    } else {
                        continue
                    }

                    let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Movie \(streamID)"
                    let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
                    let finalName = trimmedName.isEmpty ? name : trimmedName

                    let iconURLString = dict["stream_icon"] as? String
                    let logoURL = iconURLString.flatMap { URL(string: $0) }

                    let catID = String(describing: dict["category_id"] ?? "")
                    let groupName = categoryMap[catID] ?? "Movies"
                    let ext = (dict["container_extension"] as? String) ?? "mp4"

                    let streamURLString = "\(cleanBase)/movie/\(username)/\(password)/\(streamID).\(ext)"
                    guard let streamURL = URL(string: streamURLString) else {
                        continue
                    }

                    let channel = Channel(
                        id: UUID(),
                        name: finalName,
                        uniformName: finalName,
                        group: groupName,
                        logoURL: logoURL,
                        streamURL: streamURL,
                        streamURLString: streamURLString,
                        category: .movies
                    )
                    movies.append(channel)
                }

                return movies
            }
        }.value
    }

    /// Fetches all on-demand series from an Xtream Codes server
    static func fetchXtreamSeries(baseURL: String, username: String, password: String) async -> [Channel] {
        guard !username.isEmpty, !password.isEmpty else { return [] }
        let cleanBase = cleanBaseURL(baseURL)

        // 1. Fetch series categories
        var categoryMap: [String: String] = [:]
        if let catURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_series_categories") {
            var catRequest = URLRequest(url: catURL)
            catRequest.timeoutInterval = 15
            catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

            if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
               let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
                for item in catList {
                    let catID = String(describing: item["category_id"] ?? "")
                    let catName = item["category_name"] as? String ?? "Series"
                    categoryMap[catID] = catName
                }
            }
        }

        // 2. Fetch series via download to file (Zero-RAM spike)
        guard let seriesURL = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_series") else {
            return []
        }

        var seriesRequest = URLRequest(url: seriesURL)
        seriesRequest.timeoutInterval = 45
        seriesRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (tempFileURL, response) = try? await URLSession.shared.download(for: seriesRequest),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        return await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let inputStream = InputStream(url: tempFileURL) else { return [] }
                inputStream.open()
                defer { inputStream.close() }

                guard let seriesList = try? JSONSerialization.jsonObject(with: inputStream) as? [[String: Any]] else {
                    return []
                }

                var series: [Channel] = []
                series.reserveCapacity(seriesList.count)

                for dict in seriesList {
                    let seriesID: String
                    if let idInt = dict["series_id"] as? Int {
                        seriesID = String(idInt)
                    } else if let idStr = dict["series_id"] as? String, !idStr.isEmpty {
                        seriesID = idStr
                    } else {
                        continue
                    }

                    let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Series \(seriesID)"
                    let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
                    let finalName = trimmedName.isEmpty ? name : trimmedName

                    let iconURLString = (dict["cover"] as? String) ?? (dict["stream_icon"] as? String)
                    let logoURL = iconURLString.flatMap { URL(string: $0) }

                    let catID = String(describing: dict["category_id"] ?? "")
                    let groupName = categoryMap[catID] ?? "Series"

                    let streamURLString = "\(cleanBase)/series/\(username)/\(password)/\(seriesID).mp4"
                    guard let streamURL = URL(string: streamURLString) else {
                        continue
                    }

                    let channel = Channel(
                        id: UUID(),
                        name: finalName,
                        uniformName: finalName,
                        group: groupName,
                        logoURL: logoURL,
                        streamURL: streamURL,
                        streamURLString: streamURLString,
                        category: .series
                    )
                    series.append(channel)
                }

                return series
            }
        }.value
    }

    static func cleanBaseURL(_ urlString: String) -> String {
        var clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.lowercased().hasPrefix("http://") && !clean.lowercased().hasPrefix("https://") {
            clean = "http://\(clean)"
        }
        while clean.hasSuffix("/") {
            clean.removeLast()
        }
        if clean.lowercased().hasSuffix("/get.php") {
            clean = String(clean.dropLast(8))
        } else if clean.lowercased().hasSuffix("/player_api.php") {
            clean = String(clean.dropLast(15))
        }
        return clean
    }

    /// Fetches detailed series info and all episodes by season for an Xtream Codes series
    static func fetchSeriesInfo(
        baseURL: String,
        username: String,
        password: String,
        seriesID: String
    ) async throws -> XtreamSeriesInfo {
        let cleanBase = cleanBaseURL(baseURL)
        guard let url = URL(string: "\(cleanBase)/player_api.php?username=\(username)&password=\(password)&action=get_series_info&series_id=\(seriesID)") else {
            throw PlaylistError.unavailable
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw PlaylistError.unavailable
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaylistError.unavailable
        }

        let infoDict = json["info"] as? [String: Any] ?? [:]
        let episodesDict = json["episodes"] as? [String: [[String: Any]]] ?? [:]

        let name = (infoDict["name"] as? String) ?? "Series \(seriesID)"
        let plot = (infoDict["plot"] as? String) ?? (infoDict["description"] as? String)
        let cast = infoDict["cast"] as? String
        let director = infoDict["director"] as? String
        let genre = infoDict["genre"] as? String
        let releaseDate = (infoDict["release_date"] as? String) ?? (infoDict["releaseDate"] as? String)
        let rating = String(describing: infoDict["rating"] ?? "")
        let coverURL = (infoDict["cover"] as? String).flatMap { URL(string: $0) }

        var backdropURL: URL? = nil
        if let backdrops = infoDict["backdrop_path"] as? [String], let first = backdrops.first {
            backdropURL = URL(string: first)
        }

        var episodesBySeason: [Int: [XtreamEpisode]] = [:]
        var seasonsSet = Set<Int>()

        for (seasonKey, epList) in episodesDict {
            let seasonNum = Int(seasonKey) ?? 1
            seasonsSet.insert(seasonNum)
            var seasonEpisodes: [XtreamEpisode] = []

            for ep in epList {
                let epID = String(describing: ep["id"] ?? "")
                guard !epID.isEmpty else { continue }

                let epNum = (ep["episode_num"] as? Int) ?? (Int(String(describing: ep["episode_num"] ?? "1")) ?? 1)
                let title = (ep["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Episode \(epNum)"
                let ext = (ep["container_extension"] as? String) ?? "mp4"

                let epInfo = ep["info"] as? [String: Any]
                let duration = epInfo?["duration"] as? String
                let epPlot = epInfo?["plot"] as? String

                let streamURLString = "\(cleanBase)/series/\(username)/\(password)/\(epID).\(ext)"
                guard let streamURL = URL(string: streamURLString) else { continue }

                let episode = XtreamEpisode(
                    id: epID,
                    episodeNum: epNum,
                    title: title,
                    season: seasonNum,
                    containerExtension: ext,
                    duration: duration,
                    plot: epPlot,
                    streamURL: streamURL
                )
                seasonEpisodes.append(episode)
            }

            seasonEpisodes.sort { $0.episodeNum < $1.episodeNum }
            episodesBySeason[seasonNum] = seasonEpisodes
        }

        let sortedSeasons = seasonsSet.sorted()

        return XtreamSeriesInfo(
            name: name,
            plot: plot,
            cast: cast,
            director: director,
            genre: genre,
            releaseDate: releaseDate,
            rating: rating.isEmpty ? nil : rating,
            coverURL: coverURL,
            backdropURL: backdropURL,
            seasons: sortedSeasons,
            episodesBySeason: episodesBySeason
        )
    }
}

// MARK: - Xtream Series & Episode Models

struct XtreamEpisode: Identifiable, Sendable {
    let id: String
    let episodeNum: Int
    let title: String
    let season: Int
    let containerExtension: String
    let duration: String?
    let plot: String?
    let streamURL: URL
}

struct XtreamSeriesInfo: Sendable {
    let name: String
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let coverURL: URL?
    let backdropURL: URL?
    let seasons: [Int]
    let episodesBySeason: [Int: [XtreamEpisode]]
}

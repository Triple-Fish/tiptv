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
    guard let url = apiURL(cleanBase: cleanBase, username: username, password: password) else {
      return false
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return false
      }
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let userInfo = json["user_info"] as? [String: Any],
        let auth = userInfo["auth"] as? Int, auth == 1
      {
        return true
      }
    } catch {
      return false
    }
    return false
  }

  /// Fetches all live channels from an Xtream Codes server
  static func fetchXtreamChannels(baseURL: String, username: String, password: String) async throws
    -> [Channel]
  {
    let cleanBase = cleanBaseURL(baseURL)

    // 1. Fetch categories
    var categoryMap: [String: String] = [:]
    if let catURL = apiURL(
      cleanBase: cleanBase, username: username, password: password, action: "get_live_categories")
    {
      var catRequest = URLRequest(url: catURL)
      catRequest.timeoutInterval = 15
      catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

      if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
        let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]]
      {
        for item in catList {
          let catID = String(describing: item["category_id"] ?? "")
          let catName = item["category_name"] as? String ?? "General"
          categoryMap[catID] = catName
        }
      }
    }

    // 2. Fetch live streams
    guard
      let streamsURL = apiURL(
        cleanBase: cleanBase, username: username, password: password, action: "get_live_streams")
    else {
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

    let categories = categoryMap
    return try await cancellableDetached {
      guard let streamList = try? JSONSerialization.jsonObject(with: streamData) as? [[String: Any]]
      else {
        throw PlaylistError.unavailable
      }

      // Pre-classify known categories once to eliminate 30,000+ regex and string checks
      var categoryClassificationMap: [String: ChannelCategory] = [:]
      for (catID, groupName) in categories {
        categoryClassificationMap[catID] = ChannelCategory.classify(
          group: groupName, name: groupName)
      }

      var channels: [Channel] = []
      channels.reserveCapacity(streamList.count)

      for (index, dict) in streamList.enumerated() {
        if index.isMultiple(of: 1_000) { try Task.checkCancellation() }
        let streamID: String
        if let idInt = dict["stream_id"] as? Int {
          streamID = String(idInt)
        } else if let idStr = dict["stream_id"] as? String, !idStr.isEmpty {
          streamID = idStr
        } else {
          continue
        }

        let name =
          (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          ?? "Channel \(streamID)"
        let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
        let finalName = trimmedName.isEmpty ? name : trimmedName

        let iconURLString = dict["stream_icon"] as? String
        let logoURL = iconURLString.flatMap { URL(string: $0) }

        let catID = String(describing: dict["category_id"] ?? "")
        let groupName = categories[catID] ?? "Live TV"
        let resolvedCat = categoryClassificationMap[catID] ?? .other

        guard
          let streamURL = streamURL(
            cleanBase: cleanBase, kind: "live", username: username, password: password,
            fileName: "\(streamID).m3u8")
        else {
          continue
        }
        let streamURLString = streamURL.absoluteString

        let channel = Channel(
          name: finalName,
          uniformName: finalName,
          group: groupName,
          logoURL: logoURL,
          streamURL: streamURL,
          streamURLString: streamURLString,
          category: resolvedCat,
          isMovie: false,
          isSeries: false
        )
        channels.append(channel)
      }

      guard !channels.isEmpty else {
        throw PlaylistError.noChannels
      }

      return channels
    }
  }

  /// Fetches all on-demand movies (VOD) from an Xtream Codes server
  static func fetchXtreamVOD(baseURL: String, username: String, password: String) async -> [Channel]
  {
    guard !username.isEmpty, !password.isEmpty else { return [] }
    let cleanBase = cleanBaseURL(baseURL)

    // 1. Fetch VOD categories
    var categoryMap: [String: String] = [:]
    if let catURL = apiURL(
      cleanBase: cleanBase, username: username, password: password, action: "get_vod_categories")
    {
      var catRequest = URLRequest(url: catURL)
      catRequest.timeoutInterval = 15
      catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

      if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
        let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]]
      {
        for item in catList {
          let catID = String(describing: item["category_id"] ?? "")
          let catName = item["category_name"] as? String ?? "Movies"
          categoryMap[catID] = catName
        }
      }
    }

    // 2. Fetch VOD streams
    guard
      let vodURL = apiURL(
        cleanBase: cleanBase, username: username, password: password, action: "get_vod_streams")
    else {
      return []
    }

    var vodRequest = URLRequest(url: vodURL)
    vodRequest.timeoutInterval = 30
    vodRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (vodData, response) = try await URLSession.shared.data(for: vodRequest)
      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return []
      }

      let categories = categoryMap
      return try await cancellableDetached {
        guard let streamList = try? JSONSerialization.jsonObject(with: vodData) as? [[String: Any]]
        else {
          return []
        }

        var movies: [Channel] = []
        movies.reserveCapacity(streamList.count)

        for (index, dict) in streamList.enumerated() {
          if index.isMultiple(of: 1_000) { try Task.checkCancellation() }
          let streamID: String
          if let idInt = dict["stream_id"] as? Int {
            streamID = String(idInt)
          } else if let idStr = dict["stream_id"] as? String, !idStr.isEmpty {
            streamID = idStr
          } else {
            continue
          }

          let name =
            (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Movie \(streamID)"
          let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
          let finalName = trimmedName.isEmpty ? name : trimmedName

          let iconURLString = dict["stream_icon"] as? String
          let logoURL = iconURLString.flatMap { URL(string: $0) }

          let catID = String(describing: dict["category_id"] ?? "")
          let groupName = categories[catID] ?? "Movies"
          let ext = (dict["container_extension"] as? String) ?? "mp4"

          guard
            let streamURL = streamURL(
              cleanBase: cleanBase, kind: "movie", username: username, password: password,
              fileName: "\(streamID).\(ext)")
          else {
            continue
          }
          let streamURLString = streamURL.absoluteString

          let channel = Channel(
            name: finalName,
            uniformName: finalName,
            group: groupName,
            logoURL: logoURL,
            streamURL: streamURL,
            streamURLString: streamURLString,
            category: .movies,
            isMovie: true,
            isSeries: false
          )
          movies.append(channel)
        }

        return movies
      }
    } catch {
      return []
    }
  }

  /// Fetches all on-demand series from an Xtream Codes server
  static func fetchXtreamSeries(baseURL: String, username: String, password: String) async
    -> [Channel]
  {
    guard !username.isEmpty, !password.isEmpty else { return [] }
    let cleanBase = cleanBaseURL(baseURL)

    // 1. Fetch series categories
    var categoryMap: [String: String] = [:]
    if let catURL = apiURL(
      cleanBase: cleanBase, username: username, password: password, action: "get_series_categories")
    {
      var catRequest = URLRequest(url: catURL)
      catRequest.timeoutInterval = 15
      catRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

      if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
        let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]]
      {
        for item in catList {
          let catID = String(describing: item["category_id"] ?? "")
          let catName = item["category_name"] as? String ?? "Series"
          categoryMap[catID] = catName
        }
      }
    }

    // 2. Fetch series streams
    guard
      let seriesURL = apiURL(
        cleanBase: cleanBase, username: username, password: password, action: "get_series")
    else {
      return []
    }

    var seriesRequest = URLRequest(url: seriesURL)
    seriesRequest.timeoutInterval = 30
    seriesRequest.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (seriesData, response) = try await URLSession.shared.data(for: seriesRequest)
      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return []
      }

      let categories = categoryMap
      return try await cancellableDetached {
        guard
          let seriesList = try? JSONSerialization.jsonObject(with: seriesData) as? [[String: Any]]
        else {
          return []
        }

        var series: [Channel] = []
        series.reserveCapacity(seriesList.count)

        for (index, dict) in seriesList.enumerated() {
          if index.isMultiple(of: 1_000) { try Task.checkCancellation() }
          let seriesID: String
          if let idInt = dict["series_id"] as? Int {
            seriesID = String(idInt)
          } else if let idStr = dict["series_id"] as? String, !idStr.isEmpty {
            seriesID = idStr
          } else {
            continue
          }

          let name =
            (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Series \(seriesID)"
          let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "# -=_*"))
          let finalName = trimmedName.isEmpty ? name : trimmedName

          let iconURLString = (dict["cover"] as? String) ?? (dict["stream_icon"] as? String)
          let logoURL = iconURLString.flatMap { URL(string: $0) }

          let catID = String(describing: dict["category_id"] ?? "")
          let groupName = categories[catID] ?? "Series"

          guard
            let streamURL = streamURL(
              cleanBase: cleanBase, kind: "series", username: username, password: password,
              fileName: "\(seriesID).mp4")
          else {
            continue
          }
          let streamURLString = streamURL.absoluteString

          let channel = Channel(
            name: finalName,
            uniformName: finalName,
            group: groupName,
            logoURL: logoURL,
            streamURL: streamURL,
            streamURLString: streamURLString,
            category: .series,
            isMovie: false,
            isSeries: true
          )
          series.append(channel)
        }

        return series
      }
    } catch {
      return []
    }
  }

  nonisolated private static func cancellableDetached<Value: Sendable>(
    operation: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    let task = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  nonisolated private static func apiURL(
    cleanBase: String,
    username: String,
    password: String,
    action: String? = nil,
    additionalQueryItems: [URLQueryItem] = []
  ) -> URL? {
    guard var components = URLComponents(string: "\(cleanBase)/player_api.php") else { return nil }
    var queryItems = [
      URLQueryItem(name: "username", value: username),
      URLQueryItem(name: "password", value: password),
    ]
    if let action {
      queryItems.append(URLQueryItem(name: "action", value: action))
    }
    queryItems.append(contentsOf: additionalQueryItems)
    components.queryItems = queryItems
    return components.url
  }

  nonisolated private static func streamURL(
    cleanBase: String,
    kind: String,
    username: String,
    password: String,
    fileName: String
  ) -> URL? {
    guard let baseURL = URL(string: cleanBase) else { return nil }
    return [kind, username, password, fileName].reduce(baseURL) { url, component in
      url.appendingPathComponent(component)
    }
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

  /// Fetches detailed series metadata including episode list broken down by season
  static func fetchSeriesInfo(baseURL: String, username: String, password: String, seriesID: String)
    async -> XtreamSeriesInfo?
  {
    guard !username.isEmpty, !password.isEmpty, !seriesID.isEmpty else { return nil }
    let cleanBase = cleanBaseURL(baseURL)

    guard
      let infoURL = apiURL(
        cleanBase: cleanBase,
        username: username,
        password: password,
        action: "get_series_info",
        additionalQueryItems: [URLQueryItem(name: "series_id", value: seriesID)]
      )
    else {
      return nil
    }

    var request = URLRequest(url: infoURL)
    request.timeoutInterval = 20
    request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        return nil
      }

      return try await cancellableDetached {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          return nil
        }

        let info = root["info"] as? [String: Any] ?? [:]
        let name = (info["name"] as? String) ?? "Series Details"
        let plot = info["plot"] as? String
        let cast = info["cast"] as? String
        let director = info["director"] as? String
        let genre = info["genre"] as? String
        let releaseDate = info["releaseDate"] as? String
        let rating = (info["rating"] as? String) ?? ""
        let coverURL = (info["cover"] as? String).flatMap { URL(string: $0) }
        let backdropURL = ((info["backdrop_path"] as? [String])?.first).flatMap { URL(string: $0) }

        var episodesBySeason: [Int: [XtreamEpisode]] = [:]
        var seasonsSet: Set<Int> = []

        if let episodesDict = root["episodes"] as? [String: [[String: Any]]] {
          for (seasonIndex, season) in episodesDict.enumerated() {
            if seasonIndex.isMultiple(of: 100) { try Task.checkCancellation() }
            let (seasonKey, epArray) = season
            guard let seasonNum = Int(seasonKey) else { continue }
            seasonsSet.insert(seasonNum)
            var seasonEpisodes: [XtreamEpisode] = []

            for (episodeIndex, epDict) in epArray.enumerated() {
              if episodeIndex.isMultiple(of: 1_000) { try Task.checkCancellation() }
              guard let epID = String(describing: epDict["id"] ?? "").nonEmpty else { continue }
              let epNum =
                (epDict["episode_num"] as? Int)
                ?? (Int(String(describing: epDict["episode_num"] ?? "")) ?? 1)
              let title =
                (epDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Episode \(epNum)"
              let ext = (epDict["container_extension"] as? String) ?? "mp4"
              let epInfo = epDict["info"] as? [String: Any]
              let duration = epInfo?["duration"] as? String
              let epPlot = epInfo?["plot"] as? String

              guard
                let streamURL = streamURL(
                  cleanBase: cleanBase, kind: "series", username: username, password: password,
                  fileName: "\(epID).\(ext)")
              else { continue }

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
    } catch {
      return nil
    }
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

extension String {
  fileprivate nonisolated var nonEmpty: String? {
    isEmpty ? nil : self
  }
}

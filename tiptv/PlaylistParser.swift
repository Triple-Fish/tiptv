import Foundation

enum PlaylistError: LocalizedError {
  case unavailable
  case noChannels
  case unauthorized

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "The playlist could not be downloaded. Check the URL and credentials."
    case .noChannels:
      return "No playable channels were found in this playlist."
    case .unauthorized:
      return "Authentication failed (401/403). Please verify your username and password."
    }
  }
}
enum PlaylistParser {
  // Static pre-compiled regular expressions for fast linear-time matching
  nonisolated private static let prefixRegexes: [NSRegularExpression] = [
    #"^[A-Za-z]{2,4}\s*[:|\-•/]\s*"#,
    #"^\[[A-Za-z]{2,4}\]\s*"#,
    #"^\|[A-Za-z]{2,4}\|\s*"#,
    #"^(VIP|HD|FHD|4K|RAW)\s*[:|\-•/]\s*"#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

  nonisolated private static let suffixRegexes: [NSRegularExpression] = [
    #"\s*\((BACKUP|BACK-UP|BACK UP|1080P|720P|50FPS|60FPS|25FPS|HEVC|H265|H\.265|RAW|LOW)\)"#,
    #"\s*\[(BACKUP|BACK-UP|BACK UP|1080P|720P|50FPS|60FPS|25FPS|HEVC|H265|H\.265|RAW|LOW)\]"#,
    #"\s+\b(50FPS|60FPS|25FPS|RAW)\b"#,
  ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

  nonisolated private static let acronyms: Set<String> = [
    "UK", "US", "USA", "GB", "CA", "AU", "NZ", "IE", "FR", "DE", "ES", "IT", "NL",
    "HD", "FHD", "UHD", "4K", "8K", "SD", "HEVC", "H265", "RAW",
    "TV", "VIP", "PPV", "VOD", "EPG",
    "BBC", "ITV", "CNN", "HBO", "SKY", "TNT", "ESPN", "NBC", "CBS", "ABC", "FOX", "MTV",
    "BT", "MLB", "NBA", "NFL", "NHL", "UFC", "WWE", "F1", "FIA",
  ]

  /// Parses a downloaded playlist incrementally so the complete file is never retained as a String.
  nonisolated static func channels(fromFileURL fileURL: URL) async throws -> [Channel] {
    let fileHandle: FileHandle
    do {
      fileHandle = try FileHandle(forReadingFrom: fileURL)
    } catch {
      throw PlaylistError.unavailable
    }
    defer { try? fileHandle.close() }

    var channels: [Channel] = []
    channels.reserveCapacity(10_000)
    var name = ""
    var tvgID: String?
    var group: String?
    var logoURL: URL?
    var parsedLineCount = 0

    do {
      for try await rawLine in fileHandle.bytes.lines {
        parsedLineCount += 1
        if parsedLineCount.isMultiple(of: 1_000) {
          try Task.checkCancellation()
        }

        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }

        if line.hasPrefix("#EXTINF:") {
          name =
            line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "Untitled Channel"
          tvgID = attribute(named: "tvg-id", in: line)
          group = attribute(named: "group-title", in: line)
          logoURL = attribute(named: "tvg-logo", in: line).flatMap(URL.init(string:))
        } else if !line.hasPrefix("#") {
          let streamURL =
            URL(string: line)
            ?? URL(string: line.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
          if let streamURL {
            let rawName = name.isEmpty ? (streamURL.host ?? "Untitled Channel") : name
            let cleanedName = cleanSeparators(rawName)
            let cleanedGroup = group.map(cleanSeparators)
            let uniform = uniformChannelName(cleanedName)
            let category = ChannelCategory.classify(group: cleanedGroup, name: cleanedName)

            channels.append(
              Channel(
                name: cleanedName,
                tvgID: tvgID,
                uniformName: uniform,
                group: cleanedGroup,
                logoURL: logoURL,
                streamURL: streamURL,
                streamURLString: line,
                category: category
              )
            )
          }
          name = ""
          tvgID = nil
          group = nil
          logoURL = nil
        }
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PlaylistError.unavailable
    }

    return channels
  }

  /// Fast line-by-line enumerator without intermediate array allocation
  nonisolated static func channels(from playlist: String) -> [Channel] {
    var channels: [Channel] = []
    channels.reserveCapacity(min(playlist.count / 80, 50000))
    var name = ""
    var tvgID: String?
    var group: String?
    var logoURL: URL?

    playlist.enumerateLines { rawLine, _ in
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { return }

      if line.hasPrefix("#EXTINF:") {
        name = line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "Untitled Channel"
        tvgID = attribute(named: "tvg-id", in: line)
        group = attribute(named: "group-title", in: line)
        logoURL = attribute(named: "tvg-logo", in: line).flatMap(URL.init(string:))
      } else if !line.hasPrefix("#") {
        let streamURL =
          URL(string: line)
          ?? URL(string: line.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        if let streamURL {
          let rawName = name.isEmpty ? (streamURL.host ?? "Untitled Channel") : name
          let cleanedName = cleanSeparators(rawName)
          let cleanedGroup = group.map(cleanSeparators)
          let uniform = uniformChannelName(cleanedName)
          let cat = ChannelCategory.classify(group: cleanedGroup, name: cleanedName)

          channels.append(
            Channel(
              name: cleanedName,
              tvgID: tvgID,
              uniformName: uniform,
              group: cleanedGroup,
              logoURL: logoURL,
              streamURL: streamURL,
              streamURLString: line,
              category: cat
            )
          )
        }
        name = ""
        tvgID = nil
        group = nil
        logoURL = nil
      }
    }

    return channels
  }

  nonisolated static func uniformChannelName(_ raw: String) -> String {
    var text = raw.contains(";") ? cleanSeparators(raw) : raw

    // Fast prefix check: skips 4 regex passes if no prefix delimiters exist
    let hasPrefixChars = text.contains {
      $0 == ":" || $0 == "|" || $0 == "[" || $0 == "-" || $0 == "•" || $0 == "/"
    }
    if hasPrefixChars {
      for regex in prefixRegexes {
        let range = NSRange(text.startIndex..., in: text)
        text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
      }
    }

    // Fast suffix check: skips 3 regex passes if no suffix markers exist
    let hasSuffixChars =
      text.contains(")") || text.contains("]") || text.contains("FPS") || text.contains("RAW")
    if hasSuffixChars {
      for regex in suffixRegexes {
        let range = NSRange(text.startIndex..., in: text)
        text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
      }
    }

    if text.contains("|") {
      text = text.replacingOccurrences(of: "|", with: " ")
    }
    if text.contains("  ") {
      text = text.split(separator: " ").joined(separator: " ")
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty
      && (text.first == ":" || text.first == "-" || text.first == "•" || text.first == "/"
        || text.first == " ")
    {
      text = text.trimmingCharacters(in: CharacterSet(charactersIn: ":|-•/ "))
    }

    if !text.isEmpty {
      text = formatComponent(text)
    }

    return text.isEmpty ? raw : text
  }

  nonisolated static func cleanSeparators(_ text: String) -> String {
    guard text.contains(";") else { return text }

    let parts =
      text
      .components(separatedBy: ";")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard !parts.isEmpty else { return text }

    return
      parts
      .map { formatComponent($0) }
      .joined(separator: " • ")
  }

  nonisolated private static func formatComponent(_ text: String) -> String {
    let words = text.components(separatedBy: .whitespaces)
    let formattedWords = words.map { word -> String in
      let upper = word.uppercased()

      if acronyms.contains(upper) {
        return upper
      }

      if word.count > 2 && word == upper && word.rangeOfCharacter(from: .letters) != nil {
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
      }

      return word
    }
    return formattedWords.joined(separator: " ")
  }

  nonisolated private static func attribute(named name: String, in line: String) -> String? {
    let doubleQuoteTarget = name + "=\""
    if let startRange = line.range(of: doubleQuoteTarget) {
      let remainder = line[startRange.upperBound...]
      if let quoteRange = remainder.firstIndex(of: "\"") {
        return String(remainder[..<quoteRange])
      }
    }
    let singleQuoteTarget = name + "='"
    if let startRange = line.range(of: singleQuoteTarget) {
      let remainder = line[startRange.upperBound...]
      if let quoteRange = remainder.firstIndex(of: "'") {
        return String(remainder[..<quoteRange])
      }
    }
    return nil
  }
}

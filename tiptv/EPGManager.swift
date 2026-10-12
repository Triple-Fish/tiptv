import Foundation
import Observation

struct EPGProgram: Identifiable, Sendable, Equatable {
    let id: UUID
    let channelId: UUID
    let title: String
    let subtitle: String?
    let synopsis: String
    let category: String
    let startTime: Date
    let endTime: Date

    var isLive: Bool { Date() >= startTime && Date() <= endTime }

    var progress: Double {
        let duration = endTime.timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(startTime) / duration))
    }

    var timeRangeString: String {
        "\(startTime.formatted(date: .omitted, time: .shortened)) – \(endTime.formatted(date: .omitted, time: .shortened))"
    }

    var durationString: String {
        Duration.seconds(endTime.timeIntervalSince(startTime)).formatted(.units(allowed: [.hours, .minutes]))
    }

    var remainingTimeString: String {
        guard isLive else { return "" }
        return "Ends in \(Duration.seconds(endTime.timeIntervalSinceNow).formatted(.units(allowed: [.hours, .minutes])))"
    }
}

@MainActor
@Observable
final class EPGManager {
    static let shared = EPGManager()

    private(set) var programsByChannelID: [UUID: [EPGProgram]] = [:]
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var sourceURL: URL?

    private init() {}

    func programs(for channel: Channel, date: Date = Date()) -> [EPGProgram] {
        programsByChannelID[channel.id] ?? []
    }

    func currentProgram(for channel: Channel) -> EPGProgram? {
        let now = Date()
        return programs(for: channel).first { $0.startTime <= now && $0.endTime >= now }
    }

    func nextProgram(for channel: Channel) -> EPGProgram? {
        let now = Date()
        return programs(for: channel).first { $0.startTime > now }
    }

    func load(from url: URL, channels: [Channel], force: Bool = false) async {
        if !force, sourceURL == url, let lastUpdated, Date().timeIntervalSince(lastUpdated) < 6 * 60 * 60 {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let parsed = try XMLTVParser.parse(fileURL: temporaryURL, channels: channels)
            programsByChannelID = parsed
            sourceURL = url
            lastUpdated = Date()
        } catch {
            errorMessage = "The programme guide could not be loaded. Check the XMLTV URL."
        }
    }

    func clearCache() {
        programsByChannelID.removeAll(keepingCapacity: false)
        sourceURL = nil
        lastUpdated = nil
        errorMessage = nil
    }
}

final class XMLTVParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private struct RawProgram {
        let externalChannelID: String
        let start: Date
        let stop: Date
        var title = ""
        var subtitle: String?
        var description = ""
        var category = ""
    }

    private var channelNames: [String: [String]] = [:]
    private var rawPrograms: [RawProgram] = []
    private var currentChannelID: String?
    private var currentProgram: RawProgram?
    private var currentElement = ""
    private var text = ""

    static func parse(fileURL: URL, channels: [Channel]) throws -> [UUID: [EPGProgram]] {
        guard let parser = XMLParser(contentsOf: fileURL) else { throw URLError(.cannotParseResponse) }
        let delegate = XMLTVParser()
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return delegate.match(channels: channels)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        text = ""
        if elementName == "channel" {
            currentChannelID = attributeDict["id"]
        } else if elementName == "programme",
                  let channel = attributeDict["channel"],
                  let start = Self.parseDate(attributeDict["start"]),
                  let stop = Self.parseDate(attributeDict["stop"]) {
            currentProgram = RawProgram(externalChannelID: channel, start: start, stop: stop)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "display-name", let currentChannelID, !value.isEmpty {
            channelNames[currentChannelID, default: []].append(value)
        } else if currentProgram != nil {
            switch elementName {
            case "title": currentProgram?.title = value
            case "sub-title": currentProgram?.subtitle = value.isEmpty ? nil : value
            case "desc": currentProgram?.description = value
            case "category": currentProgram?.category = value
            case "programme":
                if let currentProgram, !currentProgram.title.isEmpty { rawPrograms.append(currentProgram) }
                currentProgram = nil
            default: break
            }
        }
        if elementName == "channel" { currentChannelID = nil }
        text = ""
    }

    private func match(channels: [Channel]) -> [UUID: [EPGProgram]] {
        var lookup: [String: UUID] = [:]
        for channel in channels where !channel.isVOD {
            if let tvgID = channel.tvgID, !tvgID.isEmpty { lookup[Self.key(tvgID)] = channel.id }
            lookup[Self.key(channel.name)] = channel.id
            lookup[Self.key(channel.uniformName)] = channel.id
        }
        for (externalID, names) in channelNames {
            if let channelID = lookup[Self.key(externalID)] ?? names.lazy.compactMap({ lookup[Self.key($0)] }).first {
                lookup[Self.key(externalID)] = channelID
            }
        }

        var result: [UUID: [EPGProgram]] = [:]
        for raw in rawPrograms {
            guard let channelID = lookup[Self.key(raw.externalChannelID)] else { continue }
            let stableKey = "\(channelID.uuidString)|\(raw.start.timeIntervalSince1970)|\(raw.title)"
            result[channelID, default: []].append(EPGProgram(
                id: Channel.stableID(for: stableKey), channelId: channelID, title: raw.title,
                subtitle: raw.subtitle, synopsis: raw.description, category: raw.category,
                startTime: raw.start, endTime: raw.stop
            ))
        }
        for key in result.keys { result[key]?.sort { $0.startTime < $1.startTime } }
        return result
    }

    private static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let patterns = ["yyyyMMddHHmmss Z", "yyyyMMddHHmm Z", "yyyyMMddHHmmss", "yyyyMMddHHmm"]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

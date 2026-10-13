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

    nonisolated var isLive: Bool { Date() >= startTime && Date() <= endTime }

    nonisolated var progress: Double {
        let duration = endTime.timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(startTime) / duration))
    }

    nonisolated var timeRangeString: String {
        "\(startTime.formatted(date: .omitted, time: .shortened)) – \(endTime.formatted(date: .omitted, time: .shortened))"
    }

    nonisolated var durationString: String {
        Duration.seconds(endTime.timeIntervalSince(startTime)).formatted(.units(allowed: [.hours, .minutes]))
    }

    nonisolated var remainingTimeString: String {
        guard isLive else { return "" }
        return "Ends in \(Duration.seconds(endTime.timeIntervalSinceNow).formatted(.units(allowed: [.hours, .minutes])))"
    }
}

struct EPGSourceChannel: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let aliases: [String]
}

struct EPGDiagnostics: Sendable, Equatable {
    var playlistChannelCount = 0
    var matchedChannelCount = 0
    var sourceChannelCount = 0
    var programmeCount = 0

    var unmatchedChannelCount: Int { max(0, playlistChannelCount - matchedChannelCount) }
    var matchPercentage: Int {
        guard playlistChannelCount > 0 else { return 0 }
        return Int((Double(matchedChannelCount) / Double(playlistChannelCount) * 100).rounded())
    }
}

private struct XMLTVRawProgram: Sendable {
    let externalChannelID: String
    let start: Date
    let stop: Date
    var title = ""
    var subtitle: String?
    var description = ""
    var category = ""
}

private struct XMLTVDocument: Sendable {
    let channelNames: [String: [String]]
    let rawPrograms: [XMLTVRawProgram]

    nonisolated func match(channels: [Channel], overrides: [String: String]) -> XMLTVMatchResult {
        var lookup: [String: UUID] = [:]
        var sourceByChannelID: [UUID: String] = [:]

        for channel in channels where !channel.isVOD {
            if let override = overrides[channel.streamURLString] {
                lookup[Self.key(override)] = channel.id
                sourceByChannelID[channel.id] = override
            }
            if let tvgID = channel.tvgID, !tvgID.isEmpty {
                lookup[Self.key(tvgID)] = channel.id
            }
            lookup[Self.key(channel.name)] = channel.id
            lookup[Self.key(channel.uniformName)] = channel.id
        }

        for (externalID, names) in channelNames {
            if let channelID = lookup[Self.key(externalID)] ?? names.lazy.compactMap({ lookup[Self.key($0)] }).first {
                lookup[Self.key(externalID)] = channelID
                sourceByChannelID[channelID] = externalID
            }
        }

        var programs: [UUID: [EPGProgram]] = [:]
        for raw in rawPrograms {
            guard let channelID = lookup[Self.key(raw.externalChannelID)] else { continue }
            sourceByChannelID[channelID] = raw.externalChannelID
            let stableKey = "\(channelID.uuidString)|\(raw.start.timeIntervalSince1970)|\(raw.title)"
            programs[channelID, default: []].append(EPGProgram(
                id: Channel.stableID(for: stableKey),
                channelId: channelID,
                title: raw.title,
                subtitle: raw.subtitle,
                synopsis: raw.description,
                category: raw.category,
                startTime: raw.start,
                endTime: raw.stop
            ))
        }
        for key in programs.keys { programs[key]?.sort { $0.startTime < $1.startTime } }

        let sources = channelNames.map { id, names in
            EPGSourceChannel(id: id, displayName: names.first ?? id, aliases: names)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return XMLTVMatchResult(programs: programs, sources: sources, sourceByChannelID: sourceByChannelID)
    }

    nonisolated private static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}

private struct XMLTVMatchResult: Sendable {
    let programs: [UUID: [EPGProgram]]
    let sources: [EPGSourceChannel]
    let sourceByChannelID: [UUID: String]
}

@MainActor
@Observable
final class EPGManager {
    static let shared = EPGManager()

    private(set) var programsByChannelID: [UUID: [EPGProgram]] = [:]
    private(set) var sourceChannels: [EPGSourceChannel] = []
    private(set) var matchedSourceByChannelID: [UUID: String] = [:]
    private(set) var diagnostics = EPGDiagnostics()
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var sourceURL: URL?

    private var activeLoadID: UUID?
    private var currentDocument: XMLTVDocument?
    private var currentChannels: [Channel] = []
    private var overrides: [String: String]
    private let overridesKey = "tiptv_epg_channel_overrides_v1"

    private init() {
        overrides = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:]
    }

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

    func isManuallyMatched(_ channel: Channel) -> Bool {
        overrides[channel.streamURLString] != nil
    }

    func load(from url: URL, channels: [Channel], force: Bool = false) async {
        if !force, sourceURL == url, let lastUpdated, Date().timeIntervalSince(lastUpdated) < 6 * 60 * 60 {
            if currentChannels.map(\.id) != channels.map(\.id), let currentDocument {
                await apply(document: currentDocument, channels: channels)
            }
            return
        }

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let document = try await Task.detached(priority: .userInitiated) {
                try XMLTVParser.parse(fileURL: temporaryURL)
            }.value
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            currentDocument = document
            sourceURL = url
            lastUpdated = Date()
            await apply(document: document, channels: channels)
        } catch is CancellationError {
            // A newer load has superseded this request.
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = "The programme guide could not be loaded. Your previous guide has been kept."
        }

        if activeLoadID == loadID {
            activeLoadID = nil
            isLoading = false
        }
    }

    func assign(sourceChannelID: String, to channel: Channel) async {
        overrides[channel.streamURLString] = sourceChannelID
        saveOverrides()
        guard let currentDocument else { return }
        await apply(document: currentDocument, channels: currentChannels)
    }

    func clearAssignment(for channel: Channel) async {
        overrides.removeValue(forKey: channel.streamURLString)
        saveOverrides()
        guard let currentDocument else { return }
        await apply(document: currentDocument, channels: currentChannels)
    }

    func clearCache() {
        activeLoadID = nil
        programsByChannelID.removeAll(keepingCapacity: false)
        sourceChannels = []
        matchedSourceByChannelID = [:]
        diagnostics = EPGDiagnostics()
        currentDocument = nil
        currentChannels = []
        sourceURL = nil
        lastUpdated = nil
        errorMessage = nil
        isLoading = false
    }

    private func apply(document: XMLTVDocument, channels: [Channel]) async {
        let overrides = overrides
        let result = await Task.detached(priority: .userInitiated) {
            document.match(channels: channels, overrides: overrides)
        }.value
        guard !Task.isCancelled else { return }
        currentChannels = channels
        programsByChannelID = result.programs
        sourceChannels = result.sources
        matchedSourceByChannelID = result.sourceByChannelID
        let liveChannelCount = channels.lazy.filter { !$0.isVOD }.count
        diagnostics = EPGDiagnostics(
            playlistChannelCount: liveChannelCount,
            matchedChannelCount: result.programs.keys.count,
            sourceChannelCount: result.sources.count,
            programmeCount: result.programs.values.reduce(0) { $0 + $1.count }
        )
    }

    private func saveOverrides() {
        UserDefaults.standard.set(overrides, forKey: overridesKey)
    }
}

nonisolated final class XMLTVParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var channelNames: [String: [String]] = [:]
    private var rawPrograms: [XMLTVRawProgram] = []
    private var currentChannelID: String?
    private var currentProgram: XMLTVRawProgram?
    private var text = ""
    private let dateFormatters: [DateFormatter] = {
        ["yyyyMMddHHmmss Z", "yyyyMMddHHmm Z", "yyyyMMddHHmmss", "yyyyMMddHHmm"].map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    fileprivate nonisolated static func parse(fileURL: URL) throws -> XMLTVDocument {
        guard let parser = XMLParser(contentsOf: fileURL) else { throw URLError(.cannotParseResponse) }
        let delegate = XMLTVParser()
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return XMLTVDocument(channelNames: delegate.channelNames, rawPrograms: delegate.rawPrograms)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "channel" {
            currentChannelID = attributeDict["id"]
        } else if elementName == "programme",
                  let channel = attributeDict["channel"],
                  let start = parseDate(attributeDict["start"]),
                  let stop = parseDate(attributeDict["stop"]) {
            currentProgram = XMLTVRawProgram(externalChannelID: channel, start: start, stop: stop)
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

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

import Foundation
import Observation

struct ContinueWatchingEntry: Codable, Identifiable, Sendable {
    var id: UUID { channel.id }
    let channel: Channel
    var position: Double
    var duration: Double
    var updatedAt: Date

    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

@MainActor
@Observable
final class ContinueWatchingManager {
    static let shared = ContinueWatchingManager()

    private(set) var entries: [ContinueWatchingEntry]
    private var lastPersistedAt: [UUID: Date] = [:]
    private let storageKey = "tiptv_continue_watching_v1"

    private init() {
        entries = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([ContinueWatchingEntry].self, from: $0) } ?? []
    }

    func position(for channel: Channel) -> Double? {
        entries.first { $0.channel.id == channel.id }?.position
    }

    func record(channel: Channel, position: Double, duration: Double, force: Bool = false) {
        guard channel.isVOD, position.isFinite, duration.isFinite, duration > 60 else { return }
        if position / duration >= 0.95 {
            remove(channel)
            return
        }
        guard position >= 15 else { return }
        let now = Date()
        if !force, let last = lastPersistedAt[channel.id], now.timeIntervalSince(last) < 10 { return }
        lastPersistedAt[channel.id] = now
        let entry = ContinueWatchingEntry(channel: channel, position: position, duration: duration, updatedAt: now)
        entries.removeAll { $0.channel.id == channel.id }
        entries.insert(entry, at: 0)
        if entries.count > 30 { entries.removeLast(entries.count - 30) }
        persist()
    }

    func remove(_ channel: Channel) {
        entries.removeAll { $0.channel.id == channel.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

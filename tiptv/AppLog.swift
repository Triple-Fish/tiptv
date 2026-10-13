import OSLog

enum AppLog {
  nonisolated static let playback = Logger(subsystem: "com.graham.tiptv", category: "Playback")
  nonisolated static let persistence = Logger(
    subsystem: "com.graham.tiptv", category: "Persistence")
  nonisolated static let purchases = Logger(subsystem: "com.graham.tiptv", category: "Purchases")
}

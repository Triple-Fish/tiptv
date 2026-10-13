import Foundation
import Observation

struct PlaylistProfile: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  var name: String
  var playlistURL: String
  var username: String
  var epgURL: String

  init(
    id: UUID = UUID(), name: String, playlistURL: String, username: String = "", epgURL: String = ""
  ) {
    self.id = id
    self.name = name
    self.playlistURL = playlistURL
    self.username = username
    self.epgURL = epgURL
  }
}

@MainActor
@Observable
final class PlaylistProfileStore {
  static let shared = PlaylistProfileStore()

  private(set) var profiles: [PlaylistProfile]
  private(set) var selectedProfileID: UUID?

  var selectedProfile: PlaylistProfile? {
    profiles.first { $0.id == selectedProfileID }
  }

  private let profilesKey = "tiptv_playlist_profiles_v1"
  private let selectedKey = "tiptv_selected_playlist_profile_v1"

  private init() {
    let defaults = UserDefaults.standard
    profiles =
      defaults.data(forKey: profilesKey)
      .flatMap { try? JSONDecoder().decode([PlaylistProfile].self, from: $0) } ?? []
    selectedProfileID = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))

    if profiles.isEmpty, let legacyURL = defaults.string(forKey: "playlistURL"), !legacyURL.isEmpty
    {
      let profile = PlaylistProfile(name: "My Playlist", playlistURL: legacyURL)
      profiles = [profile]
      selectedProfileID = profile.id
      persist()
    } else if selectedProfile == nil {
      selectedProfileID = profiles.first?.id
      persist()
    }
  }

  @discardableResult
  func save(name: String, playlistURL: String, username: String, epgURL: String) -> PlaylistProfile
  {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let profile = PlaylistProfile(
      name: trimmedName.isEmpty ? "Playlist \(profiles.count + 1)" : trimmedName,
      playlistURL: playlistURL,
      username: username,
      epgURL: epgURL
    )
    profiles.append(profile)
    selectedProfileID = profile.id
    persist()
    return profile
  }

  func updateSelected(playlistURL: String, username: String, epgURL: String) {
    guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
    profiles[index].playlistURL = playlistURL
    profiles[index].username = username
    profiles[index].epgURL = epgURL
    persist()
  }

  func select(_ profile: PlaylistProfile) {
    selectedProfileID = profile.id
    persist()
  }

  func delete(_ profile: PlaylistProfile) {
    profiles.removeAll { $0.id == profile.id }
    if selectedProfileID == profile.id {
      selectedProfileID = profiles.first?.id
    }
    persist()
  }

  func deleteSelected() {
    guard let selectedProfile else { return }
    delete(selectedProfile)
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(profiles) {
      UserDefaults.standard.set(data, forKey: profilesKey)
    }
    UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: selectedKey)
  }
}

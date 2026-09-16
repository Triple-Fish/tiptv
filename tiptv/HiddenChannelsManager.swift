//
//  HiddenChannelsManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class HiddenChannelsManager: ObservableObject {
    static let shared = HiddenChannelsManager()

    private let userDefaultsKey = "tiptv_hidden_channel_urls"

    @Published private(set) var hiddenStreamURLs: Set<String> = []

    init() {
        if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            hiddenStreamURLs = Set(saved)
        }
    }

    func isHidden(_ channel: Channel) -> Bool {
        hiddenStreamURLs.contains(channel.streamURLString)
    }

    func hideChannel(_ channel: Channel) {
        hiddenStreamURLs.insert(channel.streamURLString)
        persist()
    }

    func unhideChannel(_ channel: Channel) {
        hiddenStreamURLs.remove(channel.streamURLString)
        persist()
    }

    func unhideAll() {
        hiddenStreamURLs.removeAll()
        persist()
    }

    func filterVisible(from channels: [Channel]) -> [Channel] {
        if hiddenStreamURLs.isEmpty { return channels }
        return channels.filter { !hiddenStreamURLs.contains($0.streamURLString) }
    }

    func filterHidden(from channels: [Channel]) -> [Channel] {
        if hiddenStreamURLs.isEmpty { return [] }
        return channels.filter { hiddenStreamURLs.contains($0.streamURLString) }
    }

    private func persist() {
        UserDefaults.standard.set(Array(hiddenStreamURLs), forKey: userDefaultsKey)
    }
}

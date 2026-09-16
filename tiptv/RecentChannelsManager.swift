//
//  RecentChannelsManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class RecentChannelsManager: ObservableObject {
    static let shared = RecentChannelsManager()

    private let userDefaultsKey = "tiptv_recent_channel_urls"
    private let maxRecentCount = 10

    @Published private(set) var recentStreamURLs: [String] = []

    init() {
        if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            recentStreamURLs = saved
        }
    }

    func recordChannel(_ channel: Channel) {
        let url = channel.streamURLString
        var list = recentStreamURLs
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > maxRecentCount {
            list = Array(list.prefix(maxRecentCount))
        }
        recentStreamURLs = list
        UserDefaults.standard.set(list, forKey: userDefaultsKey)
    }

    func filterRecent(from allChannels: [Channel]) -> [Channel] {
        guard !recentStreamURLs.isEmpty else { return [] }
        var map: [String: Channel] = [:]
        map.reserveCapacity(recentStreamURLs.count)
        let urlSet = Set(recentStreamURLs)
        for ch in allChannels {
            if urlSet.contains(ch.streamURLString) {
                map[ch.streamURLString] = ch
                if map.count == recentStreamURLs.count {
                    break
                }
            }
        }
        return recentStreamURLs.compactMap { map[$0] }
    }

    func clearRecent() {
        recentStreamURLs = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

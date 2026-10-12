//
//  FavoritesManager.swift
//  tiptv
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FavoritesManager {
    static let shared = FavoritesManager()

    private let userDefaultsKey = "tiptv_favorite_stream_urls"

    private(set) var favoriteStreamURLs: Set<String> = []

    init() {
        if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            favoriteStreamURLs = Set(saved)
        }
    }

    func isFavorite(_ channel: Channel) -> Bool {
        favoriteStreamURLs.contains(channel.streamURLString)
    }

    func toggleFavorite(_ channel: Channel) {
        let url = channel.streamURLString
        if favoriteStreamURLs.contains(url) {
            favoriteStreamURLs.remove(url)
        } else {
            favoriteStreamURLs.insert(url)
        }
        persist()
    }

    func addFavorite(_ channel: Channel) {
        favoriteStreamURLs.insert(channel.streamURLString)
        persist()
    }

    func removeFavorite(_ channel: Channel) {
        favoriteStreamURLs.remove(channel.streamURLString)
        persist()
    }

    func filterFavorites(from channels: [Channel]) -> [Channel] {
        guard !favoriteStreamURLs.isEmpty else { return [] }
        var result: [Channel] = []
        result.reserveCapacity(min(favoriteStreamURLs.count, channels.count))
        for ch in channels {
            if favoriteStreamURLs.contains(ch.streamURLString) {
                result.append(ch)
                if result.count == favoriteStreamURLs.count {
                    break
                }
            }
        }
        return result
    }

    private func persist() {
        UserDefaults.standard.set(Array(favoriteStreamURLs), forKey: userDefaultsKey)
    }
}

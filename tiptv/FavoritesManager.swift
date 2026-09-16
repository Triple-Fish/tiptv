//
//  FavoritesManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    private let userDefaultsKey = "tiptv_favorite_urls"

    @Published private(set) var favoriteStreamURLs: Set<String> = []

    init() {
        if let saved = (UserDefaults.standard.array(forKey: userDefaultsKey) ?? UserDefaults.standard.array(forKey: "tivvy_favorite_urls")) as? [String] {
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
        if favoriteStreamURLs.isEmpty { return [] }
        return channels.filter { favoriteStreamURLs.contains($0.streamURLString) }
    }

    private func persist() {
        UserDefaults.standard.set(Array(favoriteStreamURLs), forKey: userDefaultsKey)
    }
}

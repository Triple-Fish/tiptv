import Foundation

enum ChannelCatalog {
    nonisolated static func visibleChannels(
        in channels: [Channel],
        hiddenStreamURLs: Set<String>
    ) -> [Channel] {
        guard !hiddenStreamURLs.isEmpty else { return channels }
        return channels.filter { !hiddenStreamURLs.contains($0.streamURLString) }
    }

    nonisolated static func filteredChannels(
        in channels: [Channel],
        category: ChannelCategory,
        favoriteStreamURLs: Set<String>,
        query: String
    ) -> [Channel] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return channels.filter { channel in
            if category == .favorites {
                guard favoriteStreamURLs.contains(channel.streamURLString) else { return false }
            } else if category != .all && channel.category != category {
                return false
            }
            return normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery)
        }
    }

    nonisolated static func favoriteChannels(
        in channels: [Channel],
        favoriteStreamURLs: Set<String>,
        query: String = ""
    ) -> [Channel] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return channels.filter { channel in
            favoriteStreamURLs.contains(channel.streamURLString)
                && (normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery))
        }
    }

    nonisolated static func videoChannels(
        in channels: [Channel],
        group: String?,
        pathExtension: String?,
        query: String
    ) -> [Channel] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return channels.filter { channel in
            if let group, channel.group != group { return false }
            if let pathExtension,
               channel.streamURL.pathExtension.caseInsensitiveCompare(pathExtension) != .orderedSame {
                return false
            }
            return normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery)
        }
    }
}

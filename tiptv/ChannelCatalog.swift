import Foundation

enum ChannelCatalog {
  nonisolated static func visibleChannels(
    in channels: [Channel],
    hiddenStreamURLs: Set<String>
  ) -> [Channel] {
    guard !hiddenStreamURLs.isEmpty else { return channels }
    var result: [Channel] = []
    result.reserveCapacity(channels.count)
    for (index, channel) in channels.enumerated() {
      if index.isMultiple(of: 1_000), Task.isCancelled { return [] }
      if !hiddenStreamURLs.contains(channel.streamURLString) {
        result.append(channel)
      }
    }
    return result
  }

  nonisolated static func filteredChannels(
    in channels: [Channel],
    category: ChannelCategory,
    favoriteStreamURLs: Set<String>,
    query: String
  ) -> [Channel] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if category == .all && normalizedQuery.isEmpty {
      return channels
    }
    var result: [Channel] = []
    result.reserveCapacity(channels.count)
    for (index, channel) in channels.enumerated() {
      if index.isMultiple(of: 1_000), Task.isCancelled { return [] }
      if category == .favorites {
        guard favoriteStreamURLs.contains(channel.streamURLString) else { continue }
      } else if category != .all && channel.category != category {
        continue
      }
      if normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery) {
        result.append(channel)
      }
    }
    return result
  }

  nonisolated static func favoriteChannels(
    in channels: [Channel],
    favoriteStreamURLs: Set<String>,
    query: String = ""
  ) -> [Channel] {
    guard !favoriteStreamURLs.isEmpty else { return [] }
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var result: [Channel] = []
    result.reserveCapacity(min(channels.count, favoriteStreamURLs.count))
    for (index, channel) in channels.enumerated() {
      if index.isMultiple(of: 1_000), Task.isCancelled { return [] }
      if favoriteStreamURLs.contains(channel.streamURLString),
        normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery)
      {
        result.append(channel)
      }
    }
    return result
  }

  nonisolated static func videoChannels(
    in channels: [Channel],
    group: String?,
    pathExtension: String?,
    query: String
  ) -> [Channel] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if group == nil && pathExtension == nil && normalizedQuery.isEmpty {
      return channels
    }
    var result: [Channel] = []
    result.reserveCapacity(channels.count)
    for (index, channel) in channels.enumerated() {
      if index.isMultiple(of: 1_000), Task.isCancelled { return [] }
      if let group, channel.group != group { continue }
      if let pathExtension,
        channel.streamURL.pathExtension.caseInsensitiveCompare(pathExtension) != .orderedSame
      {
        continue
      }
      if normalizedQuery.isEmpty || channel.searchKey.contains(normalizedQuery) {
        result.append(channel)
      }
    }
    return result
  }
}

import Foundation
import Observation

@MainActor
@Observable
final class CatalogStore {
    var channels: [Channel] = []
    var movies: [Channel] = []
    var series: [Channel] = []
    var visibleChannels: [Channel] = []
    var filteredChannels: [Channel] = []
    var categoryCounts: [ChannelCategory: Int] = [:]
    var availableCategories: [ChannelCategory] = [.all]

    func replaceChannels(_ newChannels: [Channel], hiddenStreamURLs: Set<String>) {
        channels = newChannels
        visibleChannels = ChannelCatalog.visibleChannels(
            in: newChannels,
            hiddenStreamURLs: hiddenStreamURLs
        )
    }

    func clear() {
        channels.removeAll(keepingCapacity: false)
        movies.removeAll(keepingCapacity: false)
        series.removeAll(keepingCapacity: false)
        visibleChannels.removeAll(keepingCapacity: false)
        filteredChannels.removeAll(keepingCapacity: false)
        categoryCounts.removeAll(keepingCapacity: false)
        availableCategories = [.all]
    }
}

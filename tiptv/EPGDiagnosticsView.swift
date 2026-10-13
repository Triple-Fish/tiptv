import SwiftUI

struct EPGDiagnosticsView: View {
  let channels: [Channel]
  let reloadGuide: () -> Void
  @State private var epgManager = EPGManager.shared
  @State private var showOnlyUnmatched = true

  private var displayedChannels: [Channel] {
    let liveChannels = channels.filter { !$0.isVOD }
    guard showOnlyUnmatched else { return liveChannels }
    return liveChannels.filter { epgManager.programsByChannelID[$0.id] == nil }
  }

  var body: some View {
    List {
      EPGDiagnosticsSummary(
        diagnostics: epgManager.diagnostics,
        lastUpdated: epgManager.lastUpdated,
        isLoading: epgManager.isLoading,
        errorMessage: epgManager.errorMessage,
        reloadGuide: reloadGuide
      )

      Section {
        Toggle("Show only unmatched channels", isOn: $showOnlyUnmatched)
      }

      Section(showOnlyUnmatched ? "Unmatched Channels" : "All Channels") {
        if displayedChannels.isEmpty {
          ContentUnavailableView(
            showOnlyUnmatched ? "Every Channel Is Matched" : "No Live Channels",
            systemImage: showOnlyUnmatched ? "checkmark.circle" : "tv.slash"
          )
        } else {
          ForEach(displayedChannels) { channel in
            NavigationLink {
              EPGSourcePickerView(channel: channel)
            } label: {
              EPGChannelMatchRow(
                channelName: channel.uniformName,
                sourceName: sourceName(for: channel),
                isManual: epgManager.isManuallyMatched(channel),
                isMatched: epgManager.programsByChannelID[channel.id] != nil
              )
            }
          }
        }
      }
    }
    .navigationTitle("Programme Guide")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func sourceName(for channel: Channel) -> String? {
    guard let sourceID = epgManager.matchedSourceByChannelID[channel.id] else { return nil }
    return epgManager.sourceChannels.first { $0.id == sourceID }?.displayName ?? sourceID
  }
}

private struct EPGDiagnosticsSummary: View {
  let diagnostics: EPGDiagnostics
  let lastUpdated: Date?
  let isLoading: Bool
  let errorMessage: String?
  let reloadGuide: () -> Void

  var body: some View {
    Section("Guide Status") {
      LabeledContent(
        "Matched Channels",
        value: "\(diagnostics.matchedChannelCount) of \(diagnostics.playlistChannelCount)")
      LabeledContent("Match Rate", value: "\(diagnostics.matchPercentage)%")
      LabeledContent("XMLTV Channels", value: "\(diagnostics.sourceChannelCount)")
      LabeledContent("Programmes", value: "\(diagnostics.programmeCount)")
      if let lastUpdated {
        LabeledContent("Last Updated") {
          Text(lastUpdated, format: .dateTime.day().month().hour().minute())
        }
      }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
      Button(action: reloadGuide) {
        Label(isLoading ? "Refreshing Guide…" : "Refresh Guide", systemImage: "arrow.clockwise")
      }
      .disabled(isLoading)
    }
  }
}

private struct EPGChannelMatchRow: View {
  let channelName: String
  let sourceName: String?
  let isManual: Bool
  let isMatched: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: isMatched ? "checkmark.circle.fill" : "questionmark.circle")
        .foregroundStyle(isMatched ? .green : .orange)
      VStack(alignment: .leading, spacing: 3) {
        Text(channelName)
          .lineLimit(1)
        Text(sourceName ?? "Choose an XMLTV channel")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if isManual {
        Text("Manual")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(TipTVTheme.aqua)
      }
    }
  }
}

private struct EPGSourcePickerView: View {
  let channel: Channel
  @State private var epgManager = EPGManager.shared
  @State private var query = ""
  @State private var filteredSources: [EPGSourceChannel] = []

  var body: some View {
    List {
      if epgManager.isManuallyMatched(channel) {
        Section {
          Button("Use Automatic Matching", role: .destructive) {
            Task { await epgManager.clearAssignment(for: channel) }
          }
        }
      }

      Section("XMLTV Channels") {
        if filteredSources.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          ForEach(filteredSources) { source in
            Button {
              Task { await epgManager.assign(sourceChannelID: source.id, to: channel) }
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(source.displayName)
                  .foregroundStyle(.primary)
                if source.displayName != source.id {
                  Text(source.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle(channel.uniformName)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: "Search XMLTV channels")
    .task(id: query) {
      do {
        try await Task.sleep(for: .milliseconds(200))
      } catch {
        return
      }
      let sources = epgManager.sourceChannels
      let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
      let work = Task.detached(priority: .userInitiated) {
        guard !search.isEmpty else { return sources }
        var matches: [EPGSourceChannel] = []
        for (index, source) in sources.enumerated() {
          if index.isMultiple(of: 1_000), Task.isCancelled { return [] }
          if source.displayName.localizedCaseInsensitiveContains(search)
            || source.id.localizedCaseInsensitiveContains(search)
            || source.aliases.contains(where: { $0.localizedCaseInsensitiveContains(search) })
          {
            matches.append(source)
          }
        }
        return matches
      }
      let matches = await withTaskCancellationHandler {
        await work.value
      } onCancel: {
        work.cancel()
      }
      guard !Task.isCancelled else { return }
      filteredSources = matches
    }
  }
}

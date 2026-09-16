//
//  PlayerEnhancements.swift
//  tiptv
//

import AVFoundation
import Combine
import Foundation
import KSPlayer
import SwiftUI

// MARK: - Sleep Timer Manager

@MainActor
final class SleepTimerManager: ObservableObject {
    @Published var remainingSeconds: Int = 0
    @Published var isTimerActive: Bool = false
    private var timerTask: Task<Void, Never>?

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return "\(hours)h \(remMinutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    func setTimer(minutes: Int, onExpire: @escaping () -> Void) {
        timerTask?.cancel()
        guard minutes > 0 else {
            isTimerActive = false
            remainingSeconds = 0
            return
        }

        remainingSeconds = minutes * 60
        isTimerActive = true

        timerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { break }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                } else {
                    self.remainingSeconds = 0
                    self.isTimerActive = false
                    onExpire()
                    break
                }
            }
        }
    }

    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        isTimerActive = false
        remainingSeconds = 0
    }
}

// MARK: - Audio & Subtitles Selector Sheet

struct AudioSubtitleSelectorSheet: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var audibleGroup: AVMediaSelectionGroup?
    @State private var legibleGroup: AVMediaSelectionGroup?
    @State private var audioTracks: [AVMediaSelectionOption] = []
    @State private var subtitleTracks: [AVMediaSelectionOption] = []
    @State private var selectedAudioTrack: AVMediaSelectionOption?
    @State private var selectedSubtitleTrack: AVMediaSelectionOption?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if audioTracks.isEmpty {
                        Text("Default Audio Stream")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioTracks, id: \.self) { option in
                            Button {
                                Haptics.selection()
                                selectedAudioTrack = option
                                if let audibleGroup {
                                    player.currentItem?.select(option, in: audibleGroup)
                                }
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if option == selectedAudioTrack {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(themeManager.accent)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Label("Audio Track", systemImage: "waveform")
                        .foregroundStyle(themeManager.accent)
                }
                .listRowBackground(themeManager.currentTheme.cardBackground)

                Section {
                    Button {
                        Haptics.selection()
                        selectedSubtitleTrack = nil
                        if let legibleGroup {
                            player.currentItem?.select(nil, in: legibleGroup)
                        }
                    } label: {
                        HStack {
                            Text("Off")
                                .foregroundStyle(.white)
                            Spacer()
                            if selectedSubtitleTrack == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(themeManager.accent)
                            }
                        }
                    }

                    ForEach(subtitleTracks, id: \.self) { option in
                        Button {
                            Haptics.selection()
                            selectedSubtitleTrack = option
                            if let legibleGroup {
                                player.currentItem?.select(option, in: legibleGroup)
                            }
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .foregroundStyle(.white)
                                Spacer()
                                if option == selectedSubtitleTrack {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(themeManager.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Subtitles & Captions", systemImage: "captions.bubble")
                        .foregroundStyle(themeManager.accent)
                }
                .listRowBackground(themeManager.currentTheme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(themeManager.currentTheme.contentBackground.ignoresSafeArea())
            .navigationTitle("Audio & Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(themeManager.accent)
                }
            }
            .onAppear {
                loadMediaSelection()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func loadMediaSelection() {
        guard let currentItem = player.currentItem else { return }
        let asset = currentItem.asset

        Task {
            if let audible = try? await asset.loadMediaSelectionGroup(for: .audible) {
                await MainActor.run {
                    self.audibleGroup = audible
                    self.audioTracks = audible.options
                    self.selectedAudioTrack = currentItem.currentMediaSelection.selectedMediaOption(in: audible)
                }
            }

            if let legible = try? await asset.loadMediaSelectionGroup(for: .legible) {
                await MainActor.run {
                    self.legibleGroup = legible
                    self.subtitleTracks = legible.options
                    self.selectedSubtitleTrack = currentItem.currentMediaSelection.selectedMediaOption(in: legible)
                }
            }
        }
    }
}

// MARK: - MKV Audio & Subtitles Selector Sheet

struct MKVAudioSubtitleSelectorSheet: View {
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var audioTracks: [MediaPlayerTrack] = []
    @State private var selectedAudioTrackID: Int32?
    @State private var selectedSubtitleID: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if audioTracks.isEmpty {
                        Text("Default Audio Stream")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioTracks, id: \.trackID) { track in
                            Button {
                                Haptics.selection()
                                selectedAudioTrackID = track.trackID
                                coordinator.playerLayer?.player.select(track: track)
                            } label: {
                                HStack {
                                    Text(track.description.isEmpty ? track.name : track.description)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if track.trackID == selectedAudioTrackID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(themeManager.accent)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Label("Audio Track", systemImage: "waveform")
                        .foregroundStyle(themeManager.accent)
                }
                .listRowBackground(themeManager.currentTheme.cardBackground)

                Section {
                    Button {
                        Haptics.selection()
                        selectedSubtitleID = nil
                        coordinator.subtitleModel.selectedSubtitleInfo = nil
                    } label: {
                        HStack {
                            Text("Off")
                                .foregroundStyle(.white)
                            Spacer()
                            if selectedSubtitleID == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(themeManager.accent)
                            }
                        }
                    }

                    ForEach(coordinator.subtitleModel.subtitleInfos, id: \.subtitleID) { info in
                        Button {
                            Haptics.selection()
                            selectedSubtitleID = info.subtitleID
                            coordinator.subtitleModel.selectedSubtitleInfo = info
                            if let track = info as? MediaPlayerTrack {
                                coordinator.playerLayer?.player.select(track: track)
                            }
                        } label: {
                            HStack {
                                Text(info.name)
                                    .foregroundStyle(.white)
                                Spacer()
                                if info.subtitleID == selectedSubtitleID {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(themeManager.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Subtitles & Captions", systemImage: "captions.bubble")
                        .foregroundStyle(themeManager.accent)
                }
                .listRowBackground(themeManager.currentTheme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(themeManager.currentTheme.contentBackground.ignoresSafeArea())
            .navigationTitle("Audio & Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(themeManager.accent)
                }
            }
            .onAppear {
                loadTracks()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func loadTracks() {
        if let player = coordinator.playerLayer?.player {
            let audios = player.tracks(mediaType: .audio)
            self.audioTracks = audios
            self.selectedAudioTrackID = audios.first(where: { $0.isEnabled })?.trackID
        }
        self.selectedSubtitleID = coordinator.subtitleModel.selectedSubtitleInfo?.subtitleID
    }
}

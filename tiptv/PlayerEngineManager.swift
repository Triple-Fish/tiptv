//
//  PlayerEngineManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

/// Manages playback engine selection and automatic fallback for channels
/// where native AVPlayer plays audio-only due to unsupported broadcast video codecs (e.g. MPEG-2, TS).
@MainActor
final class PlayerEngineManager: ObservableObject {
    static let shared = PlayerEngineManager()

    enum EnginePreference: String, CaseIterable, Identifiable {
        case auto = "auto"
        case ffmpeg = "ffmpeg"
        case native = "native"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto (Recommended)"
            case .ffmpeg: return "Advanced (FFmpeg)"
            case .native: return "Native (AVPlayer)"
            }
        }

        var description: String {
            switch self {
            case .auto:
                return "Uses native player with auto-fallback to FFmpeg whenever a channel plays sound without video (MPEG-2 / broadcast TS)."
            case .ffmpeg:
                return "Forces FFmpeg engine for all live channels, ensuring 100% video decoding for MPEG-2, interlaced TV, and TS streams."
            case .native:
                return "Strictly uses Apple AVPlayer without FFmpeg."
            }
        }
    }

    private let prefKey = "playerEnginePreference"
    private let legacyCacheKey = "channelsRequiringFFmpegCache"
    private let cacheKey = "channelsRequiringFFmpegCache_v2"

    @Published var enginePreference: EnginePreference {
        didSet {
            UserDefaults.standard.set(enginePreference.rawValue, forKey: prefKey)
        }
    }

    /// Set of stream URLs that were detected as sound-only / MPEG-2 and require the FFmpeg engine.
    @Published private(set) var channelsRequiringFFmpeg: Set<String> = []

    /// Transient overrides during session (e.g. user manually toggled engine for current channel)
    @Published private var sessionEngineOverrides: [UUID: Bool] = [:]

    private init() {
        // Purge legacy poisoned cache where healthy streams were incorrectly recorded
        UserDefaults.standard.removeObject(forKey: legacyCacheKey)

        let savedPref = UserDefaults.standard.string(forKey: prefKey) ?? EnginePreference.auto.rawValue
        self.enginePreference = EnginePreference(rawValue: savedPref) ?? .auto

        if let saved = UserDefaults.standard.stringArray(forKey: cacheKey) {
            channelsRequiringFFmpeg = Set(saved)
        }
    }

    /// Determines whether a given channel should use the FFmpeg (KSPlayer) engine
    func shouldRunFFmpeg(for channel: Channel) -> Bool {
        // MKV files always use KSPlayer / FFmpeg
        let lower = channel.streamURLString.lowercased()
        if lower.contains(".mkv") {
            return true
        }

        // Manual session override takes highest priority
        if let override = sessionEngineOverrides[channel.id] {
            return override
        }

        switch enginePreference {
        case .ffmpeg:
            return true
        case .native:
            return false
        case .auto:
            if channelsRequiringFFmpeg.contains(channel.streamURLString) {
                return true
            }
            return false
        }
    }

    /// Marks a channel as requiring the FFmpeg engine due to sound-only / MPEG-2 detection
    func markChannelRequiresFFmpeg(_ channel: Channel) {
        channelsRequiringFFmpeg.insert(channel.streamURLString)
        UserDefaults.standard.set(Array(channelsRequiringFFmpeg), forKey: cacheKey)
    }

    /// Removes a channel from requiring FFmpeg
    func clearFFmpegForChannel(_ channel: Channel) {
        channelsRequiringFFmpeg.remove(channel.streamURLString)
        UserDefaults.standard.set(Array(channelsRequiringFFmpeg), forKey: cacheKey)
    }

    /// Clears the sound-only / MPEG-2 cache so all channels revert to native AVPlayer
    func clearFFmpegCache() {
        channelsRequiringFFmpeg.removeAll()
        sessionEngineOverrides.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    /// Toggles engine preference for the active channel during this session
    func toggleEngine(for channel: Channel, currentIsFFmpeg: Bool) -> Bool {
        let newState = !currentIsFFmpeg
        sessionEngineOverrides[channel.id] = newState
        if newState {
            markChannelRequiresFFmpeg(channel)
        } else {
            clearFFmpegForChannel(channel)
        }
        return newState
    }
}

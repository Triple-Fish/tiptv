//
//  tiptvApp.swift
//  tiptv
//

import AVFoundation
import SwiftUI

@main
struct TipTVApp: App {
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Boost URL cache to 50MB RAM and 250MB disk for smooth channel artwork scrolling
    URLCache.shared = URLCache(
      memoryCapacity: 50 * 1024 * 1024,
      diskCapacity: 250 * 1024 * 1024,
      diskPath: "tiptv_artwork_cache"
    )

    // Configure audio session category safely without blocking the launch thread
    #if !os(macOS)
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          IdleTimerManager.setDisabled(false)
        }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase != .active {
        PlaylistCredentials.shared.flushPendingChanges()
      }
    }
  }
}

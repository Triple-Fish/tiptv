//
//  MKVPlayerView.swift
//  tiptv
//

import Foundation
import KSPlayer
import SwiftUI

struct MKVPlayerView: View {
  let url: URL
  let coordinator: KSVideoPlayer.Coordinator
  var isAspectFill: Bool = false

  init(url: URL, coordinator: KSVideoPlayer.Coordinator, isAspectFill: Bool = false) {
    self.url = url
    self.coordinator = coordinator
    self.isAspectFill = isAspectFill
  }

  private var options: KSOptions {
    let opt = KSOptions()
    opt.hardwareDecode = true
    opt.autoDeInterlace = false
    opt.userAgent = XtreamService.defaultUserAgent
    opt.appendHeader(["User-Agent": XtreamService.defaultUserAgent])
    return opt
  }

  var body: some View {
    KSVideoPlayer(coordinator: coordinator, url: url, options: options)
      .id(url)
      .allowsHitTesting(false)
      .onChange(of: isAspectFill) { _, fill in
        coordinator.isScaleAspectFill = fill
      }
      .onAppear {
        coordinator.isScaleAspectFill = isAspectFill
      }
      .onDisappear {
        coordinator.playerLayer?.pause()
        coordinator.playerLayer?.stop()
        coordinator.resetPlayer()
        IdleTimerManager.setDisabled(false)
      }
  }
}

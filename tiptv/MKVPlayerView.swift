//
//  MKVPlayerView.swift
//  tiptv
//

import Foundation
import KSPlayer
import SwiftUI

struct MKVPlayerView: View {
    let url: URL
    var coordinator: KSVideoPlayer.Coordinator? = nil
    var isAspectFill: Bool = false

    @StateObject private var fallbackCoordinator = KSVideoPlayer.Coordinator()

    private var activeCoordinator: KSVideoPlayer.Coordinator {
        coordinator ?? fallbackCoordinator
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
        KSVideoPlayer(coordinator: activeCoordinator, url: url, options: options)
            .allowsHitTesting(false)
            .onChange(of: isAspectFill) { _, fill in
                activeCoordinator.isScaleAspectFill = fill
            }
            .onAppear {
                activeCoordinator.isScaleAspectFill = isAspectFill
            }
            .onDisappear {
                activeCoordinator.playerLayer?.pause()
                activeCoordinator.resetPlayer()
            }
    }
}

//
//  PiPManager.swift
//  tiptv
//

import AVKit
import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class PiPManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let shared = PiPManager()

    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    private(set) var pipController: AVPictureInPictureController?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func setup(with playerLayer: AVPlayerLayer) {
        guard isSupported else { return }

        if pipController?.playerLayer === playerLayer { return }

        pipController?.delegate = nil
        pipController = nil

        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            return
        }

        controller.delegate = self
        #if os(iOS) || os(tvOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        self.pipController = controller
        self.isPiPPossible = controller.isPictureInPicturePossible
    }

    func togglePiP() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    func startPiP() {
        pipController?.startPictureInPicture()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isPiPActive = false
        print("PiP failed to start: \(error.localizedDescription)")
    }
}

// MARK: - Cross-Platform PiP Video Player Representable

#if canImport(UIKit)
struct PiPVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var isAspectFill: Bool = false

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
        PiPManager.shared.setup(with: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            PiPManager.shared.setup(with: uiView.playerLayer)
        }
        uiView.playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
#elseif canImport(AppKit)
struct PiPVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var isAspectFill: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
        view.wantsLayer = true
        view.layer = playerLayer
        PiPManager.shared.setup(with: playerLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = nsView.layer as? AVPlayerLayer {
            if playerLayer.player !== player {
                playerLayer.player = player
                PiPManager.shared.setup(with: playerLayer)
            }
            playerLayer.videoGravity = isAspectFill ? .resizeAspectFill : .resizeAspect
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if let playerLayer = nsView.layer as? AVPlayerLayer {
            playerLayer.player = nil
        }
    }
}
#endif

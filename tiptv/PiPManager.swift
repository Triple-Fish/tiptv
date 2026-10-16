//
//  PiPManager.swift
//  tiptv
//

import AVKit
import Combine
import Foundation
import OSLog
import SwiftUI
import UIKit

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
    let possible = controller.isPictureInPicturePossible
    if self.isPiPPossible != possible {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if self.isPiPPossible != possible {
          self.isPiPPossible = possible
        }
      }
    }
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

  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isPiPActive = true
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isPiPActive = true
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isPiPActive = false
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isPiPActive = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    isPiPActive = false
    AppLog.playback.error("PiP failed to start: \(error.localizedDescription, privacy: .public)")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}

// MARK: - iPhone PiP Video Player Representable

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
    if !PiPManager.shared.isPiPActive {
      uiView.playerLayer.player = nil
    }
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
}

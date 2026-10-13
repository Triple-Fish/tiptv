import AVKit
import SwiftUI
import UIKit

struct AirPlayRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.prioritizesVideoDevices = true
    picker.tintColor = .white
    picker.activeTintColor = UIColor(TipTVTheme.aqua)
    return picker
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

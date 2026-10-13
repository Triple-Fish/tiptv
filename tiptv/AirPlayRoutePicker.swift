import AVKit
import SwiftUI

#if canImport(UIKit)
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
#elseif canImport(AppKit)
  struct AirPlayRoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
      let picker = AVRoutePickerView()
      picker.prioritizesVideoDevices = true
      return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
  }
#endif

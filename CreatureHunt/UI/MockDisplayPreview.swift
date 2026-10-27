#if DEBUG
  import MWDATMockDevice
  import SwiftUI

  /// Shows what simulated Meta Ray-Ban Display glasses would show in the lens.
  struct MockDisplayPreview: UIViewRepresentable {
    let display: any MockDisplayKit

    func makeUIView(context: Context) -> UIView {
      display.createPreviewView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
  }
#endif

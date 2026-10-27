import SwiftUI
import UIKit

/// Same palette as the web prototype: dawn sage by day, deep teal night in dark mode,
/// with a firefly-amber lantern.
enum Theme {
  static let background = dynamic(light: 0xDDE7DF, dark: 0x0E2A2D)
  static let surface = dynamic(light: 0xEEF3EE, dark: 0x163A3C)
  static let ink = dynamic(light: 0x1E3833, dark: 0xE3EDD3)
  static let muted = dynamic(light: 0x4F6D65, dark: 0x8EAAA0)
  static let accent = dynamic(light: 0x9A5C0D, dark: 0xF2B33D)
  static let beam = dynamic(light: 0xE39B2C, dark: 0xF2B33D)
  static let ring = dynamic(light: 0x9FB7AE, dark: 0x2F5552)
  static let onAccent = dynamic(light: 0xFFF8EC, dark: 0x1B2A1C)

  static let titleFont = Font.system(size: 28, weight: .heavy, design: .serif)
  static let headingFont = Font.system(size: 24, weight: .heavy, design: .serif)

  private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(
      UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
      })
  }
}

extension UIColor {
  fileprivate convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1)
  }
}

extension Double {
  /// "12.3 s"
  var secondsText: String { String(format: "%.1f s", self) }
}

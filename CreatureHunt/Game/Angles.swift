import Foundation

/// Angle helpers. All angles are in degrees, clockwise-positive (turning right increases them).
enum Deg {
  /// Wraps any angle into the range -180..<180.
  static func wrap(_ angle: Double) -> Double {
    var x = (angle + 180).truncatingRemainder(dividingBy: 360)
    if x < 0 { x += 360 }
    return x - 180
  }

  static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}

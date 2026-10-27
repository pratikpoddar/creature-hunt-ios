import SwiftUI

/// The listening ring: the world around you seen from above, north up. The lantern shows
/// which way you're facing and brightens as you lock on. Caught creatures stay where you
/// found them.
struct RingView: View {
  @ObservedObject var game: GameEngine
  @State private var lastDragX: CGFloat?

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let radius = size * 0.43

      ZStack {
        Circle()
          .fill(Theme.surface)
          .overlay(Circle().stroke(Theme.ring, lineWidth: 2))
          .frame(width: radius * 2, height: radius * 2)

        Circle()
          .stroke(Theme.ring, style: StrokeStyle(lineWidth: 1.5, dash: [2, 7]))
          .frame(width: radius * 1.33, height: radius * 1.33)

        Ticks(radius: radius)
          .stroke(Theme.ring, style: StrokeStyle(lineWidth: 2, lineCap: .round))

        Wedge(halfAngle: game.tolerance, radius: radius)
          .fill(Theme.beam)
          .opacity(0.22 + game.focus * 0.6)
          .rotationEffect(.degrees(game.yaw))

        ForEach(game.catches) { caught in
          Marker(imageName: caught.creature.imageName, dashed: false)
            .offset(offset(for: caught.angle, radius: radius))
            .transition(.scale.combined(with: .opacity))
        }

        if let hint = game.hintAngle {
          Marker(imageName: nil, dashed: true)
            .offset(offset(for: hint, radius: radius))
        }

        Circle()
          .fill(Theme.ink)
          .frame(width: 16, height: 16)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if let last = lastDragX { game.nudge(by: Double(value.location.x - last) * 0.45) }
            lastDragX = value.location.x
          }
          .onEnded { _ in lastDragX = nil }
      )
      .animation(.spring(duration: 0.4), value: game.catches.count)
      .accessibilityElement()
      .accessibilityLabel("Listening ring")
      .accessibilityValue("Facing \(Int((game.yaw + 360).truncatingRemainder(dividingBy: 360))) degrees")
    }
  }

  private func offset(for angle: Double, radius: CGFloat) -> CGSize {
    let r = Deg.radians(angle)
    return CGSize(width: sin(r) * radius, height: -cos(r) * radius)
  }
}

private struct Marker: View {
  let imageName: String?
  let dashed: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(Theme.background)
        .overlay(
          Circle().stroke(
            Theme.accent, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 4] : [])))
      if let imageName {
        Image(imageName).resizable().scaledToFit().padding(4)
      } else {
        Text("?").font(.headline).foregroundStyle(Theme.accent)
      }
    }
    .frame(width: 44, height: 44)
  }
}

/// A pie slice pointing straight up, centred on the ring's middle.
private struct Wedge: Shape {
  var halfAngle: Double
  var radius: CGFloat

  var animatableData: Double {
    get { halfAngle }
    set { halfAngle = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    var path = Path()
    path.move(to: center)
    path.addArc(
      center: center, radius: radius,
      startAngle: .degrees(-90 - halfAngle), endAngle: .degrees(-90 + halfAngle),
      clockwise: false)
    path.closeSubpath()
    return path
  }
}

private struct Ticks: Shape {
  var radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    var path = Path()
    for step in 0..<12 {
      let a = Deg.radians(Double(step) * 30)
      let inner = radius * 0.907
      let outer = radius * 0.96
      path.move(to: CGPoint(x: center.x + sin(a) * inner, y: center.y - cos(a) * inner))
      path.addLine(to: CGPoint(x: center.x + sin(a) * outer, y: center.y - cos(a) * outer))
    }
    return path
  }
}

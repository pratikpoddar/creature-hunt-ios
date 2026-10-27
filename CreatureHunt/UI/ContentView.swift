import SwiftUI

struct ContentView: View {
  @ObservedObject var game: GameEngine
  @ObservedObject var glasses: GlassesManager

  var body: some View {
    VStack(spacing: 14) {
      header

      RingView(game: game)
        .overlay { panels }
        .frame(maxHeight: .infinity)

      HStack {
        Text(game.status).foregroundStyle(Theme.muted)
        Spacer()
        Text(game.elapsed.secondsText)
          .font(.body.monospacedDigit().bold())
          .accessibilityLabel("Hunt time \(game.elapsed.secondsText)")
      }

      controls
      sourcePicker
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .foregroundStyle(Theme.ink)
    .background(Theme.background.ignoresSafeArea())
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 10) {
      Image("Logo").resizable().scaledToFit().frame(width: 46, height: 46)
        .accessibilityHidden(true)
      Text("Creature Hunt").font(Theme.titleFont)
      Spacer(minLength: 8)
      HStack(spacing: 5) {
        ForEach(0..<GameEngine.creaturesPerHunt, id: \.self) { slot in
          SlotView(
            imageName: slot < game.catches.count ? game.catches[slot].creature.imageName : nil,
            isCurrent: game.phase != .intro && slot == game.index)
        }
      }
      .accessibilityElement()
      .accessibilityLabel("\(game.catches.count) of \(GameEngine.creaturesPerHunt) caught")
    }
  }

  // MARK: - Panels over the ring

  @ViewBuilder private var panels: some View {
    switch game.phase {
    case .intro:
      IntroPanel(best: game.best) { game.startHunt() }
    case .caught:
      if let caught = game.lastCatch { CatchCard(caught: caught) }
    case .done:
      DonePanel(total: game.elapsed, penalty: game.penalty, best: game.best, isNewBest: game.isNewBest) {
        game.startHunt()
      }
    case .playing:
      EmptyView()
    }
  }

  // MARK: - Controls

  private var controls: some View {
    HStack(spacing: 12) {
      TurnButton(systemImage: "chevron.left", label: "Turn left") { game.manualTurn = $0 ? -1 : 0 }
      Button("Show a hint (+5 s)") { game.useHint() }
        .buttonStyle(QuietButtonStyle())
        .disabled(game.phase != .playing)
        .frame(maxWidth: .infinity)
      TurnButton(systemImage: "chevron.right", label: "Turn right") { game.manualTurn = $0 ? 1 : 0 }
    }
  }

  private var sourcePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Turn with", selection: $game.source) {
        ForEach(HeadingSource.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      switch game.source {
      case .glasses: GlassesPanel(glasses: glasses)
      case .phone:
        Text("Hold your phone upright and turn your whole body.")
          .font(.footnote).foregroundStyle(Theme.muted)
      case .touch:
        Text("Hold the arrows or drag the ring to turn. Wear headphones.")
          .font(.footnote).foregroundStyle(Theme.muted)
      }

      Toggle("Wider catch angle (easier on glasses speakers)", isOn: $game.wideCatch)
        .font(.footnote)
        .tint(Theme.accent)
    }
  }
}

// MARK: - Glasses setup

private struct GlassesPanel: View {
  @ObservedObject var glasses: GlassesManager

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(statusLine).font(.footnote).foregroundStyle(Theme.muted)
      HStack(spacing: 12) {
        if !glasses.isRegistered {
          Button("Connect glasses") { Task { await glasses.connect() } }
            .buttonStyle(QuietButtonStyle())
        } else if !glasses.isTracking {
          Button("Try again") { glasses.startTracking() }
            .buttonStyle(QuietButtonStyle())
        }
        #if DEBUG
          Menu("Simulate") {
            Button("Ray-Ban Meta (audio only)") { glasses.useSimulatedGlasses() }
            Button("Meta Ray-Ban Display") { glasses.useSimulatedGlasses(withDisplay: true) }
          }
          .font(.footnote)
        #endif
      }
      #if DEBUG
        if let mock = glasses.mockDisplay {
          MockDisplayPreview(display: mock)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ring, lineWidth: 2))
            .accessibilityLabel("Preview of the glasses display")
        }
      #endif
      Toggle("Reverse turn direction", isOn: $glasses.invertTurn)
        .font(.footnote)
        .tint(Theme.accent)
    }
  }

  private var statusLine: String {
    if !glasses.isRegistered { return glasses.registrationText }
    if let message = glasses.trackingMessage { return message }
    if glasses.isTracking {
      let lens = glasses.hasDisplay ? " Progress shows in your lens." : ""
      return "Head tracking from \(glasses.deviceName ?? "your glasses"). Turn your head to hunt.\(lens)"
    }
    if !glasses.isDeviceConnected { return "Turn on your glasses and put them on." }
    return "Ready. Head tracking will start in a moment."
  }
}

// MARK: - Small pieces

private struct SlotView: View {
  let imageName: String?
  let isCurrent: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(imageName == nil ? Color.clear : Theme.surface)
        .overlay(
          Circle().stroke(
            imageName != nil || isCurrent ? Theme.accent : Theme.ring,
            style: StrokeStyle(lineWidth: 2, dash: imageName == nil ? [3, 3] : [])))
      if let imageName {
        Image(imageName).resizable().scaledToFit().padding(3)
      }
    }
    .frame(width: 34, height: 34)
  }
}

/// Turns while pressed and stops on release.
private struct TurnButton: View {
  let systemImage: String
  let label: String
  let onPressChange: (Bool) -> Void
  @State private var isPressed = false

  var body: some View {
    Image(systemName: systemImage)
      .font(.title2.bold())
      .frame(width: 64, height: 64)
      .background(Circle().fill(Theme.surface))
      .overlay(Circle().stroke(isPressed ? Theme.accent : Theme.ring, lineWidth: 2))
      .contentShape(Circle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            if !isPressed {
              isPressed = true
              onPressChange(true)
            }
          }
          .onEnded { _ in
            isPressed = false
            onPressChange(false)
          }
      )
      .accessibilityLabel(label)
      .accessibilityAddTraits(.isButton)
  }
}

struct QuietButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(minHeight: 48)
      .background(RoundedRectangle(cornerRadius: 14).stroke(Theme.ring, lineWidth: 2))
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(Theme.onAccent)
      .padding(.horizontal, 22)
      .padding(.vertical, 12)
      .frame(minHeight: 48)
      .background(Capsule().fill(Theme.accent))
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}

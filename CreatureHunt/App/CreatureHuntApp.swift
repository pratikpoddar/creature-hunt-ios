import MWDATCore
import SwiftUI

@main
struct CreatureHuntApp: App {
  @StateObject private var glasses: GlassesManager
  @StateObject private var game: GameEngine
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Reads the MWDAT dictionary from Info.plist. A failure here means the plist is wrong.
    do {
      try Wearables.configure()
    } catch {
      assertionFailure("Meta Wearables SDK would not configure: \(error)")
    }
    let glasses = GlassesManager()
    _glasses = StateObject(wrappedValue: glasses)
    _game = StateObject(wrappedValue: GameEngine(glasses: glasses))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(game: game, glasses: glasses)
        // Meta AI calls back here after registration and when it launches the app by voice.
        .onOpenURL { url in
          guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
          else { return }
          Task { _ = try? await Wearables.shared.handleUrl(url) }
        }
        .task {
          // “Hey Meta, start Creature Hunt” starts a hunt straight away.
          let game = game
          glasses.startObserving(onVoiceLaunch: { [weak game] in game?.startHunt() })
        }
        .onChange(of: scenePhase) { _, phase in
          game.setActive(phase == .active)
        }
    }
  }
}

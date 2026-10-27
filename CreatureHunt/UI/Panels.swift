import SwiftUI

private struct PanelBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(22)
      .frame(maxWidth: 380, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.ring, lineWidth: 2))
      .padding(.horizontal, 4)
  }
}

struct IntroPanel: View {
  let best: Double?
  let onStart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image("Logo").resizable().scaledToFit().frame(width: 76, height: 76)
        .accessibilityHidden(true)
      Text("Hear it, face it, catch it").font(Theme.headingFont)
      Text("Each creature calls from somewhere around you. Wear your glasses or headphones.")
      Text("Turn until its call sounds straight ahead and clear. Calls from behind sound muffled.")
      Text("Keep facing it while the lantern fills, and it’s yours. Five creatures per hunt.")
      if let best {
        Text("Your best hunt: \(best.secondsText).").font(.footnote).foregroundStyle(Theme.muted)
      }
      Button("Start hunting", action: onStart)
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 6)
    }
    .modifier(PanelBackground())
  }
}

struct CatchCard: View {
  let caught: GameEngine.Catch

  var body: some View {
    VStack(spacing: 8) {
      Image(caught.creature.imageName)
        .resizable().scaledToFit()
        .frame(width: 150, height: 150)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
        .accessibilityHidden(true)
      Text(caught.creature.name).font(Theme.headingFont)
      Text(caught.creature.blurb).multilineTextAlignment(.center)
      Text("Caught in \(caught.seconds.secondsText)").font(.footnote).foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity)
    .modifier(PanelBackground())
    .allowsHitTesting(false)
    .accessibilityElement(children: .combine)
  }
}

struct DonePanel: View {
  let total: Double
  let penalty: Double
  let best: Double?
  let isNewBest: Bool
  let onAgain: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("All five caught").font(Theme.headingFont)
      Text(
        penalty > 0
          ? "Total time \(total.secondsText), including \(Int(penalty)) s of hints."
          : "Total time \(total.secondsText).")
      if isNewBest {
        Text("That’s your best hunt so far.").font(.footnote).foregroundStyle(Theme.muted)
      } else if let best {
        Text("Your best is \(best.secondsText).").font(.footnote).foregroundStyle(Theme.muted)
      }
      Button("Hunt again", action: onAgain)
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 6)
    }
    .modifier(PanelBackground())
  }
}

// Kept free of SwiftUI on purpose: MWDATDisplay has its own Text, Button and Image types.
import MWDATDisplay
import UIKit

/// What the glasses' display should show. The game updates it only when something meaningful
/// changes, because each update is sent over the air and replaces the whole screen.
enum HUDScreen: Equatable {
  case intro(best: Double?)
  case hunting(number: Int, total: Int, locking: Bool)
  case caught(name: String, imageName: String, seconds: Double)
  case done(total: Double, penalty: Double, isNewBest: Bool, best: Double?)
}

/// Buttons the wearer can press on the glasses (with the Neural Band or the touchpad).
enum HUDAction {
  case start, hint
}

/// Builds the in-lens screens with Meta's Display layout components.
///
/// The game is played by ear, so the display never shows where a creature is. It shows
/// progress, the catch, and the result.
enum GlassesHUD {
  static func view(for screen: HUDScreen, onAction: @escaping @Sendable (HUDAction) -> Void) -> FlexBox {
    switch screen {
    case .intro(let best):
      let logo = thumbnail("Logo")
      return FlexBox(direction: .column, spacing: 12) {
        FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
          if let logo {
            FlexBox(direction: .column) { logo }
              .flexGrow(1)
          }
          FlexBox(direction: .column) {
            Text("Creature Hunt", style: .heading)
            Text("Listen for the call, turn your head to face it.", style: .meta, color: .secondary)
            if let best {
              Text("Best hunt: \(seconds(best))", style: .meta, color: .secondary)
            }
          }
          .flexGrow(4)
        }
        .padding(24)
        .background(.card)

        FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
          ButtonGroup {
            Button(label: "Start hunting", onClick: { onAction(.start) })
              .actionRole(.primary)
          }
        }
      }

    case .hunting(let number, let total, let locking):
      return FlexBox(direction: .column, spacing: 12) {
        FlexBox(direction: .column) {
          Text("Creature \(number) of \(total)", style: .meta, color: .secondary)
          Text(locking ? "Hold steady…" : "Listen…", style: .heading)
          Text(
            locking ? "You’re facing it. Don’t move." : "Turn until the call sounds straight ahead.",
            style: .body)
        }
        .padding(24)
        .background(.card)

        FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
          ButtonGroup {
            Button(label: "Hint (+5 s)", onClick: { onAction(.hint) })
          }
        }
      }

    case .caught(let name, let imageName, let time):
      let art = thumbnail(imageName)
      return FlexBox(direction: .column, spacing: 12) {
        FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
          if let art {
            FlexBox(direction: .column) { art }
              .flexGrow(2)
          }
          FlexBox(direction: .column) {
            Text("Caught!", style: .meta, color: .secondary)
            Text(name, style: .heading)
            Text("in \(seconds(time))", style: .body)
          }
          .flexGrow(5)
        }
        .padding(24)
        .background(.card)
      }

    case .done(let total, let penalty, let isNewBest, let best):
      let detail =
        isNewBest
        ? "Your best hunt so far."
        : best.map { "Your best is \(seconds($0))." } ?? ""
      return FlexBox(direction: .column, spacing: 12) {
        FlexBox(direction: .column) {
          Text("All five caught", style: .heading)
          Text(
            penalty > 0 ? "\(seconds(total)), including \(Int(penalty)) s of hints" : seconds(total),
            style: .body)
          Text(detail, style: .meta, color: .secondary)
        }
        .padding(24)
        .background(.card)

        FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
          ButtonGroup {
            Button(label: "Hunt again", onClick: { onAction(.start) })
              .actionRole(.primary)
          }
        }
      }
    }
  }

  private static func seconds(_ value: Double) -> String {
    String(format: "%.1f s", value)
  }

  /// A small copy of an illustration, so less data crosses to the glasses.
  private static func thumbnail(_ name: String) -> Image? {
    guard let source = UIImage(named: name) else { return nil }
    let size = CGSize(width: 160, height: 160)
    let small = UIGraphicsImageRenderer(size: size).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }
    return Image(image: small, sizePreset: .fill, cornerRadius: .medium)
  }
}

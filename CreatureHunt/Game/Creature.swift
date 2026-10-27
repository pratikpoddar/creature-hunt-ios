import Foundation

struct Creature: Identifiable, Equatable {
  let id: String
  let name: String
  let blurb: String
  let call: CallKind

  /// Name of the illustration in the asset catalog.
  var imageName: String { id }

  static let all: [Creature] = [
    Creature(id: "c-chirp", name: "Chirpling", blurb: "Sings in threes and never sits still for long.", call: .chirp),
    Creature(id: "c-hoot", name: "Hoolow", blurb: "Two low notes from somewhere just out of sight.", call: .hoot),
    Creature(id: "c-rustle", name: "Rustlebug", blurb: "You’ll hear the leaves before you see it.", call: .rustle),
    Creature(id: "c-bubble", name: "Blubwisp", blurb: "Pops softly, like a kettle about to boil.", call: .bubble),
    Creature(id: "c-tick", name: "Tickit", blurb: "Keeps perfect time and hates being found.", call: .tick),
    Creature(id: "c-croak", name: "Bogcroak", blurb: "Deep, damp and surprisingly proud of it.", call: .croak),
  ]
}

/// How hard each creature in a hunt is to catch. Later creatures are quieter, call less often,
/// need more precise aim, and the last two wander.
struct Difficulty {
  /// How far off-centre (degrees) you can be and still lock on.
  let tolerance: Double
  /// Seconds between calls.
  let interval: Double
  let volume: Float
  /// Degrees per second the creature wanders.
  let drift: Double

  static let ladder: [Difficulty] = [
    Difficulty(tolerance: 16, interval: 1.2, volume: 1.00, drift: 0),
    Difficulty(tolerance: 14, interval: 1.4, volume: 0.95, drift: 0),
    Difficulty(tolerance: 12, interval: 1.6, volume: 0.85, drift: 0),
    Difficulty(tolerance: 11, interval: 1.8, volume: 0.80, drift: 7),
    Difficulty(tolerance: 10, interval: 2.0, volume: 0.75, drift: 11),
  ]
}

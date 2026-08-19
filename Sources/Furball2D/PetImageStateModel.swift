import Foundation

/// One semantic state contract shared by every sprite-atlas appearance.
/// Continuous-video clips deliberately do not use this model: their entry and
/// exit ports remain independently declared by the video asset pipeline.
enum PetImageStateModel {
    static let identifier = "furball-image-state-v1"
    static let sleepBreathingPeriod: TimeInterval = 8.0

    struct Binding: Equatable {
        let id: String
        let animation: String
        let frameIndices: [Int]?
        let loops: Bool?
        let motion: String?
    }

    /// Row 5 is a fixed physical posture chain for every 2D pet:
    /// stand → lower → horizontal lie → eyes close → quiet sleep breaths.
    /// Keeping these semantic ports identical prevents a profile-specific
    /// frame map from redefining "sleep" as a seated or standing head dip.
    static let postureBindings: [Binding] = [
        Binding(id: "stand.idle", animation: "idle", frameIndices: nil, loops: true, motion: nil),
        Binding(id: "stand.to.sit", animation: "waiting", frameIndices: [0], loops: false, motion: nil),
        Binding(id: "sit.idle", animation: "waiting", frameIndices: nil, loops: true, motion: nil),
        Binding(id: "sit.to.lie", animation: "failed", frameIndices: [1, 2, 3], loops: false, motion: nil),
        Binding(id: "lie.idle", animation: "failed", frameIndices: [2, 3, 2], loops: true, motion: nil),
        Binding(id: "lie.to.sleep", animation: "failed", frameIndices: [2, 3, 4, 5], loops: false, motion: nil),
        // Autonomous sleep holds one canonical closed-eye pose. Breathing is
        // one continuous procedural sine wave, never an atlas-frame loop:
        // even a long four-frame cycle still produces four visible pulses.
        Binding(id: "sleep.idle", animation: "failed", frameIndices: [5], loops: true, motion: "sleep"),
        Binding(id: "sleep.to.stand", animation: "failed", frameIndices: [5, 4, 3, 2, 1, 0], loops: false, motion: nil),
    ]

    static func validates(_ bindings: [Binding]) -> Bool {
        let byID = Dictionary(bindings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return postureBindings.allSatisfy { expected in
            guard let actual = byID[expected.id] else { return false }
            return actual.animation == expected.animation
                && actual.frameIndices == expected.frameIndices
                && actual.loops == expected.loops
                && actual.motion == expected.motion
        }
    }

}

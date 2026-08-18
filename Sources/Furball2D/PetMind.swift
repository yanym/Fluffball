import Foundation

enum PetPersonalityTrait: String, CaseIterable, Codable {
    case vitality
    case curiosity
    case affection
    case composure
}

struct PetPersonalityTraits: Codable, Equatable {
    var vitality: Double
    var curiosity: Double
    var affection: Double
    var composure: Double

    static let `default` = PetPersonalityTraits(
        vitality: 0.66,
        curiosity: 0.72,
        affection: 0.78,
        composure: 0.52
    )

    subscript(trait: PetPersonalityTrait) -> Double {
        get {
            switch trait {
            case .vitality: vitality
            case .curiosity: curiosity
            case .affection: affection
            case .composure: composure
            }
        }
        set {
            let value = Self.clamp(newValue)
            switch trait {
            case .vitality: vitality = value
            case .curiosity: curiosity = value
            case .affection: affection = value
            case .composure: composure = value
            }
        }
    }

    mutating func normalize() {
        vitality = Self.clamp(vitality)
        curiosity = Self.clamp(curiosity)
        affection = Self.clamp(affection)
        composure = Self.clamp(composure)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct PetEmotionalState: Codable, Equatable {
    var energy: Double
    var curiosityNeed: Double
    var affinity: Double

    static let `default` = PetEmotionalState(
        energy: 0.76,
        curiosityNeed: 0.58,
        affinity: 0.42
    )

    mutating func adjust(energy: Double = 0, curiosity: Double = 0, affinity: Double = 0) {
        self.energy = min(1, max(0, self.energy + energy))
        curiosityNeed = min(1, max(0, curiosityNeed + curiosity))
        self.affinity = min(1, max(0, self.affinity + affinity))
    }
}

enum PetMemoryKind: String, Codable {
    case affection
    case treat
    case play
    case exploration
    case desktop
    case rest
    case appearance
}

struct PetMemoryEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let kind: PetMemoryKind
    let text: String
    let salience: Double

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, text, englishText, salience
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: PetMemoryKind,
        text: String,
        salience: Double
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
        self.salience = min(1, max(0, salience))
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        kind = try values.decode(PetMemoryKind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text)
            ?? values.decode(String.self, forKey: .englishText)
        salience = try values.decode(Double.self, forKey: .salience)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(date, forKey: .date)
        try values.encode(kind, forKey: .kind)
        try values.encode(text, forKey: .text)
        try values.encode(salience, forKey: .salience)
    }
}

struct PetMindSnapshot: Codable, Equatable {
    var traits: PetPersonalityTraits
    var state: PetEmotionalState
    var memories: [PetMemoryEvent]
    var lastUpdatedAt: Date

    static let `default` = PetMindSnapshot(
        traits: .default,
        state: .default,
        memories: [],
        lastUpdatedAt: Date()
    )

    mutating func normalize(now: Date = Date()) {
        traits.normalize()
        state.adjust()
        memories = memories
            .filter { now.timeIntervalSince($0.date) < PetMindStore.memoryLifetime }
            .sorted { $0.date > $1.date }
        if memories.count > PetMindStore.maximumMemoryCount {
            memories.removeLast(memories.count - PetMindStore.maximumMemoryCount)
        }
    }
}

extension Notification.Name {
    static let petMindDidChange = Notification.Name("Furball2D.petMindDidChange")
}

@MainActor
enum PetMindStore {
    nonisolated static let maximumMemoryCount = 12
    nonisolated static let memoryLifetime: TimeInterval = 48 * 60 * 60
    private static let schemaVersion = 1

    private static func key(for petID: String) -> String {
        "petMind.v\(schemaVersion).\(petID)"
    }

    static func load(petID: String) -> PetMindSnapshot {
        guard let data = UserDefaults.standard.data(forKey: key(for: petID)),
              var snapshot = try? JSONDecoder().decode(PetMindSnapshot.self, from: data) else {
            return .default
        }
        snapshot.normalize()
        return snapshot
    }

    static func save(_ snapshot: PetMindSnapshot, petID: String, notify: Bool = true) {
        var normalized = snapshot
        normalized.normalize()
        normalized.lastUpdatedAt = Date()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: key(for: petID))
        if notify {
            NotificationCenter.default.post(
                name: .petMindDidChange,
                object: nil,
                userInfo: ["petID": petID]
            )
        }
    }

    static func updateTraits(_ traits: PetPersonalityTraits, petID: String) {
        var snapshot = load(petID: petID)
        snapshot.traits = traits
        save(snapshot, petID: petID)
    }

    static func clearMemories(petID: String) {
        var snapshot = load(petID: petID)
        snapshot.memories.removeAll()
        save(snapshot, petID: petID)
    }

    static func record(
        petID: String,
        kind: PetMemoryKind,
        text: String,
        salience: Double = 0.55,
        energy: Double = 0,
        curiosity: Double = 0,
        affinity: Double = 0
    ) -> PetMindSnapshot {
        var snapshot = load(petID: petID)
        snapshot.state.adjust(energy: energy, curiosity: curiosity, affinity: affinity)

        // Collapse repeated low-value events so the profile remains a readable
        // short story instead of a debug log.
        let now = Date()
        let isDuplicate = snapshot.memories.first.map {
            $0.kind == kind
                && $0.text == text
                && now.timeIntervalSince($0.date) < 90
        } ?? false
        if !isDuplicate {
            snapshot.memories.insert(
                PetMemoryEvent(
                    date: now,
                    kind: kind,
                    text: text,
                    salience: salience
                ),
                at: 0
            )
        }
        save(snapshot, petID: petID)
        return snapshot
    }

    static func updateState(
        _ state: PetEmotionalState,
        petID: String,
        notify: Bool = false
    ) -> PetMindSnapshot {
        var snapshot = load(petID: petID)
        snapshot.state = state
        save(snapshot, petID: petID, notify: notify)
        return snapshot
    }
}

extension PetMindSnapshot {
    func personalitySummary(for language: AppLanguage) -> String {
        let descriptors: [(Double, String)] = [
            (traits.vitality, "playful"),
            (traits.curiosity, "curious"),
            (traits.affection, "affectionate"),
            (traits.composure, "calm")
        ]
        let strongest = descriptors.sorted { $0.0 > $1.0 }.prefix(2)
        return "A \(strongest.map { $0.1 }.joined(separator: ", ")) companion"
    }

    func contextualSpeech(for language: AppLanguage) -> [String] {
        var messages: [String] = []
        if state.energy < 0.28 {
            messages.append("My battery is a little low. Can I rest near you?")
        } else if state.energy > 0.82, traits.vitality > 0.62 {
            messages.append("I have so much energy right now. Want to play?")
        }
        if state.curiosityNeed > 0.74 {
            messages.append("Is there something new on the desktop?")
        }
        if state.affinity > 0.72 {
            messages.append("I like staying close to you more and more.")
        }
        if let memory = memories.first, Date().timeIntervalSince(memory.date) < 4 * 60 * 60 {
            messages.append("I still remember: \(memory.text)")
        }
        return messages
    }
}

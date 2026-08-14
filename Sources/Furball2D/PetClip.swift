import Foundation

enum PetPosture {
    case stand
    case sit
    case lie
    case sleep
}

struct PetClip {
    let fileName: String
    let loops: Bool
    let resultingPosture: PetPosture

    var url: URL {
        get throws {
            let relativePath = "Assets/Clips/\(fileName).mov"
            let candidates: [URL?] = [
                Bundle.main.resourceURL?.appendingPathComponent(relativePath),
                Bundle.main.bundleURL
                    .appendingPathComponent("Furball2D_Furball2D.bundle")
                    .appendingPathComponent(relativePath),
                Bundle.main.executableURL?.deletingLastPathComponent()
                    .appendingPathComponent("Furball2D_Furball2D.bundle")
                    .appendingPathComponent(relativePath)
            ]
            for candidate in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            throw PetAppError.missingAsset("\(fileName).mov")
        }
    }

    var isAvailable: Bool { (try? url) != nil }
}

struct PetMotionClipSet {
    let start: PetClip
    let loop: PetClip
    let stop: PetClip
}

enum PetClips {
    private static let viewDirectory = "left-profile"

    static let standIdle = clip("stand-idle", loops: true, posture: .stand)
    static let sitIdle = clip("sit-idle", loops: true, posture: .sit)
    static let lieIdle = clip("lie-idle", loops: true, posture: .lie)
    static let sleepIdle = clip("sleep-idle", loops: true, posture: .sleep)
    static let walk = motion("walk")
    static let slowRun = motion("slow-run")
    static let fastRun = motion("fast-run")
    static let walkIdle = walk.loop
    static let sleepToStand = clip("sleep-to-stand", loops: false, posture: .stand)
    static let sitDown = clip("stand-to-sit", loops: false, posture: .sit)
    static let sitToLie = clip("sit-to-lie", loops: false, posture: .lie)
    static let lieToSleep = clip("lie-to-sleep", loops: false, posture: .sleep)

    static func idle(for posture: PetPosture) -> PetClip {
        switch posture {
        case .stand: standIdle
        case .sit: sitIdle
        case .lie: lieIdle
        case .sleep: sleepIdle
        }
    }

    private static func clip(_ name: String, loops: Bool, posture: PetPosture) -> PetClip {
        PetClip(fileName: "\(viewDirectory)/\(name)", loops: loops, resultingPosture: posture)
    }

    private static func motion(_ name: String) -> PetMotionClipSet {
        PetMotionClipSet(
            start: clip("\(name)-start", loops: false, posture: .stand),
            loop: clip("\(name)-loop", loops: true, posture: .stand),
            stop: clip("\(name)-stop", loops: false, posture: .stand)
        )
    }
}

enum PetAppError: LocalizedError {
    case missingAsset(String)
    case metalUnavailable
    case rendererSetup(String)

    var errorDescription: String? {
        AppLanguage.stored.errorDescription(for: self)
    }
}

import CoreVideo
import Foundation

enum AppLanguage: String, Sendable {
    case english = "en"

    static let preferenceKey = "appLanguage"
    static var stored: AppLanguage { .english }

    var statusTooltip: String { "Furball Desktop Pet" }
    var interactMenu: String { "Pet / Next Action" }
    var speakMenu: String { "Say Something" }
    var throwTreatMenu: String { "Toss a Treat by Cursor" }
    var treatChaseStarted: String { "I smell a treat! Coming! 🦴" }
    var treatFound: String { "Found it! You’re the best ✨" }
    var treatTimedOut: String { "That one was extra sneaky—I’ll get it next time!" }
    var desktopInteractionsSetting: String { "Explore desktop items while roaming" }
    var sniffTrashSpeech: String { "This bin smells like it has stories." }
    func inspectDesktopItemSpeech(_ name: String) -> String { "What is “\(name)”? Can I play with it?" }
    func movedDesktopItemSpeech(_ name: String, succeeded: Bool) -> String {
        succeeded ? "I nudged “\(name)” over a little." : "“\(name)” would rather stay there. Fair enough!"
    }
    func carryingDesktopItemSpeech(_ name: String) -> String {
        "Easy now… I’ll carry “\(name)” just a tiny bit."
    }
    var hoverGreeting: String { "Were you about to pet me?" }
    var highFiveGreeting: String { "High five! You’re doing great 🙌" }
    var cuteActionsMenu: String { "Cute Actions" }
    var imageTurnMenu: String { "Look at Me" }
    var imageTurnGreeting: String { "I’m looking at you! 👀" }
    var imageTurnBusy: String { "One moment—finishing this move!" }
    var sleepMenu: String { "Go to Sleep Now" }
    var alwaysSleepMenu: String { "Always Sleep" }
    var actionsMenu: String { "Actions" }
    var treatPlacementHint: String { "Your cursor is a treat—click anywhere to toss it. Right-click to cancel." }
    func visibilityMenu(isVisible: Bool) -> String { isVisible ? "Hide Pet" : "Show Pet" }
    var passThroughMenu: String { "Click Through Completely" }
    var appearanceMenu: String { "Appearance" }
    var visualSettingsMenu: String { "Visual & Animation Settings…" }
    var settingsMenu: String { "Settings…" }
    var checkForUpdatesMenu: String { "Check for Updates…" }
    func updateAvailableMenu(_ version: String) -> String { "Download Furball \(version) ✨" }
    var petLibraryMenu: String { "Pet Library…" }
    var petLibraryTitle: String { "Pet Library" }
    var libraryTab: String { "My Pets" }
    var creatorTab: String { "Create 2D Pet" }
    var importPetPackButton: String { "Import Pet Pack…" }
    var exportPetPackButton: String { "Export…" }
    var removePetButton: String { "Remove" }
    var usePetButton: String { "Use This Pet" }
    var activePetButton: String { "Active" }
    var builtInBadge: String { "BUILT IN" }
    var appearanceCountLabel: String { "AVAILABLE APPEARANCES" }
    var personalityHeading: String { "PERSONALITY" }

    func personalityTraitTitle(_ trait: PetPersonalityTrait) -> String {
        switch trait {
        case .vitality: "Vitality"
        case .curiosity: "Curiosity"
        case .affection: "Affection"
        case .composure: "Composure"
        }
    }

    var currentStateHeading: String { "RIGHT NOW" }
    var energyStateLabel: String { "Energy" }
    var curiosityStateLabel: String { "Wonder" }
    var affinityStateLabel: String { "Bond" }
    var shortMemoryHeading: String { "RECENT MEMORIES" }
    var clearMemoriesButton: String { "Clear Memories" }
    var noMemoriesLabel: String { "No special memories yet. Spend a little time together." }
    var creatorIntro: String {
        "Choose 6–12 real photos to build a maintainable Realistic 2D pet. For lifelike continuous footage, download the separate Live Motion Skill and process one source video per action."
    }
    var oneClickCodexButton: String { "Build & Import with Codex" }
    var cancelCodexCreationButton: String { "Cancel Generation" }
    var codexNotInstalledLabel: String { "Codex CLI was not detected; request export is still available." }
    var codexCreationRunningLabel: String {
        "Codex is generating and validating the Pet Pack. This usually takes several minutes…"
    }
    var codexCreationCancelledLabel: String {
        "Generation was cancelled; the local request and log were preserved."
    }
    var codexPhotoConsentTitle: String { "Let Codex use these photos?" }
    var codexPhotoConsentBody: String {
        "Furball will launch your signed-in local Codex and provide the selected photos to its image model. Your Codex plan, usage limits, and OpenAI privacy terms apply; Furball stores no account or API key."
    }
    func codexCreationSucceeded(_ name: String) -> String {
        "\(name) was generated, validated, and imported into your library."
    }
    var petNameField: String { "Pet Name" }
    var speciesField: String { "Species" }
    var styleField: String { "Style" }
    var realisticStyleLabel: String { "Realistic 2D" }
    var choosePhotosButton: String { "Choose Photos…" }
    func selectedPhotosLabel(_ count: Int) -> String {
        count == 0 ? "No photos selected" : "\(count) photos selected"
    }
    var exportCreationRequestButton: String { "Export Creation Request…" }
    var downloadSkillButton: String { "Download 2D Creator Skill…" }
    var downloadLiveMotionSkillButton: String { "Download Live Motion Skill…" }
    var importSuccessTitle: String { "Pet Imported" }
    func importedPetMessage(_ name: String) -> String {
        "\(name) passed validation and was added to your library."
    }
    var invalidCreationInput: String {
        "Enter a name and provide 6–12 clear photos."
    }
    var visualSettingsTitle: String { "Visual & Animation" }
    var visualSettingsSubtitle: String {
        "Choose between Live Motion and the maintained Realistic 2D appearance."
    }
    var currentPetLabel: String { "CURRENT PET" }
    var includedPetLabel: String { "Built-in pet · Live Motion + Realistic 2D" }
    var appearanceSectionTitle: String { "Choose an Appearance" }
    var displaySectionTitle: String { "Display" }
    var behaviorSectionTitle: String { "Desktop Interaction" }
    var videoOptionsTitle: String { "Live Motion Options" }
    var videoOptionsUnavailable: String {
        "Image animation does not use video blending controls, so they are hidden."
    }
    var closeButton: String { "Done" }
    func appearanceChanged(_ title: String) -> String { "Switched to \(title) ✨" }
    var appearanceBusy: String { "I’ll change appearance as soon as this move finishes." }
    var imageModeEnabled: String { "Image animation mode—lightweight and cute!" }
    var videoModeEnabled: String { "Detailed video animation is back! ✨" }
    var autoBehaviorMenu: String { "Daily Routine (Sleep / Patrol)" }
    var freeRoamMenu: String { "Free Roam (Across Desktop)" }
    var followCursorMenu: String { "Follow Cursor (Move in Any Direction)" }
    var imageFacingMenu: String { "Look Toward Cursor (16 Directions)" }
    var legacyImageFacingMenu: String { "Smooth Five-Angle Head Turning" }
    var crossfadeMenu: String { "Smooth Action Transitions" }
    var freeRoamStarted: String { "I’m off to explore the desktop! 🐾" }
    var freeRoamStopped: String { "All done exploring—I’m back!" }
    var alwaysOnTopMenu: String { "Always on Top" }
    var sizeMenu: String { "Pet Size" }
    var sizeTooltip: String { "Continuously adjust the pet size" }
    var quitMenu: String { "Quit Furball" }
    var sleepConfirmation: String { "Okay, nap time! 💤" }
    var problemTitle: String { "Furball Ran Into a Problem" }
    var launchFailureTitle: String { "Furball Could Not Start" }
    var commandQueueFailure: String { "Could not create the Metal command queue" }
    var shaderFunctionsMissing: String { "Could not find the Metal shader functions" }
    var samplerFailure: String { "Could not create the Metal sampler" }
    func textureCacheFailure(_ code: CVReturn) -> String {
        "Could not create the Core Video texture cache (\(code))"
    }

    func speechMessages(for posture: PetPosture) -> [String] {
        switch posture {
        case .stand:
            [
                "I’m here to keep you company ✨",
                "You do the work—I’ll be cute.",
                "Got any head pats for me? 🐾",
                "Desktop patrol reporting for duty!",
                "Turn around—I’ll be right here.",
                "Don’t work too hard, okay?",
                "I found one very focused human!",
                "My tail says I really like you.",
                "Today’s mission: look after you.",
                "Need a little puppy energy?",
                "I’m not meddling—I’m supervising.",
                "Hey, you’re doing great today!",
                "Standing nicely earns treats, right?",
                "I think I just heard your next great idea.",
                "Big desktop. Good thing I found you.",
                "One fresh delivery of puppy encouragement.",
                "Want me to guard this window for you?",
                "My tail work is very professional today.",
                "Take one deep breath. I’m right here.",
                "Tiny paws, enormous moral support.",
                "I brought you an invisible bouquet! 🌼",
                "Your screen looked lonely, so I came over.",
                "I vote that you deserve a snack break.",
                "If you smile, I’ll wag twice as hard.",
                "I’m your pocket-sized cheering section.",
                "Boop delivery! Please sign with one smile.",
                "We make a pretty great little team."
            ]
        case .sit:
            [
                "I’m sitting nicely. Treat?",
                "The view is pretty good from here!",
                "I’m keeping a very close eye on you.",
                "Patiently waiting for a head pat.",
                "Look, I tucked my paws in!",
                "Does this pose earn a biscuit?",
                "No rush. I’ll wait right here.",
                "I’m your good pup today too.",
                "Ears up—I’m listening to you.",
                "One very focused puppy, ready!",
                "Will you play with me when you’re done?",
                "Am I sitting properly enough?",
                "Ready and waiting for cuddles!",
                "I can wait, but my ears stay hopeful.",
                "This spot is exactly close enough to you.",
                "Sitting quietly is a puppy superpower.",
                "I saved my best profile for you.",
                "Say the word—I’m listening.",
                "Coordinates locked: right beside you.",
                "This is my extra-polite treat pose.",
                "I can hear a cuddle from three windows away.",
                "My ears are holding a meeting about snacks.",
                "I saved you the coziest seat beside me.",
                "One sit, two bright eyes, zero complaints.",
                "I’m practicing my ‘too cute to ignore’ face.",
                "Your next idea has my full attention.",
                "I’ll be your tiny meeting assistant today."
            ]
        case .lie:
            [
                "Just lying here, thinking dog thoughts.",
                "Let’s enjoy a quiet moment.",
                "This floor is wonderfully cool.",
                "I saved half of this calm for you.",
                "A little rest brings back my zoomies.",
                "You work—I’ll keep things cozy.",
                "I’m not lazy. I’m in power-save mode.",
                "This spot has the perfect view of you.",
                "Paws resting, eyes keeping you company.",
                "It’s okay to take today slowly.",
                "Daydreaming is important puppy work.",
                "Want to do nothing for three seconds?",
                "Just being soft and staying close.",
                "Put your worries down. I’ll watch them.",
                "The floor is especially good for daydreams.",
                "Tail tucked in. I won’t interrupt.",
                "It’s genuinely okay to lie down for a bit.",
                "Not paused—gently loading.",
                "My quiet mode likes you too.",
                "Cozy level: maximum fluff.",
                "I flattened myself into a little cloud.",
                "Come borrow some of my calm.",
                "The floor and I are best friends now.",
                "I’m keeping this warm spot safe for you.",
                "Soft paws, soft thoughts, soft afternoon.",
                "This is a strategic cuddle position.",
                "I’m resting, but my love is still awake."
            ]
        case .sleep:
            [
                "Shh… dreaming of treats 💤",
                "Five more minutes…",
                "Zzz… remember to rest too.",
                "My tail is wagging in my dreams.",
                "Puppy battery recharging…",
                "I dreamed you gave me all the snacks!",
                "Zzz… I feel very safe today.",
                "My eyes are closed, but I’m still here.",
                "Big cuddles when I wake up.",
                "Dream patrol still counts as work, right?",
                "Downloading extra-sweet dreams…",
                "Nose resting. Ears on duty.",
                "If I snore, pretend you didn’t hear.",
                "Borrowing a cloud for my pillow…",
                "See you in my dream—bring biscuits.",
                "I’m having a very good dream about you.",
                "Quiet now… happiness is falling asleep.",
                "Finding you is task one when I wake up.",
                "Goodnight is just another way to stay close.",
                "Zzz… chasing marshmallows through the clouds.",
                "My dream has room for you too.",
                "Please hold all boops until morning.",
                "One tiny snore means I’m extra cozy.",
                "Dreaming in warm blankets and biscuits.",
                "I tucked today safely under my paws.",
                "Sleep mode: round, warm, and happy.",
                "Meet me by the treat tree in my dream."
            ]
        }
    }

    func moodTitle(for mood: PetSpeechBubbleMood) -> String {
        switch mood {
        case .stand: "FURBALL"
        case .sit: "SWEET"
        case .lie: "CHILL"
        case .sleep: "NAP TIME"
        case .active: "PLAYFUL"
        }
    }

    func errorDescription(for error: PetAppError) -> String {
        switch error {
        case .missingAsset(let name):
            "Missing asset: \(name). Run ./Scripts/build-assets.sh first."
        case .metalUnavailable:
            "No compatible Metal device is available on this Mac."
        case .rendererSetup(let details):
            "The Metal renderer could not be initialized: \(details)"
        }
    }
}

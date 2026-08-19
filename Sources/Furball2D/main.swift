import AppKit

if let validationPath = ProcessInfo.processInfo.environment["FURBALL_VALIDATE_PACK"],
   !validationPath.isEmpty {
    do {
        let summary = try PetPackLibraryManager.validatePack(
            at: URL(fileURLWithPath: validationPath, isDirectory: true)
        )
        print("Furball Pet Pack OK: \(summary.name) [\(summary.id)] · \(summary.appearanceCount) appearance(s)")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Furball Pet Pack validation failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wait one main-run-loop turn so the accessory activation policy and the
        // system status bar have both settled before creating the status item.
        // Creating it synchronously while changing activation policy can leave a
        // launch-services app without a visible recovery entry in the menu bar.
        DispatchQueue.main.async { [weak self] in
            self?.launchPet()
        }
    }

    @MainActor
    private func launchPet() {
        do {
            // Launch in the most legible full-body pose so a first-time user
            // can immediately find the pet. The normal idle routine still
            // settles it down and puts it to sleep shortly afterward.
            let controller = try PetController(startingPosture: .stand)
            petController = controller
            controller.start()
        } catch {
            let language = AppLanguage.stored
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = language.launchFailureTitle
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // Imports require the explicit in-app picker and validation flow. Do not
        // install a Finder-opened package without the same user-facing review.
        sender.reply(toOpenOrPrint: .failure)
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

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
    private var pendingPetPacks: [URL] = []

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
            let controller = try PetController(startingPosture: .sleep)
            petController = controller
            controller.start()
            for url in pendingPetPacks { controller.importPetPack(at: url) }
            pendingPetPacks.removeAll()
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
        let urls = filenames.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let petController {
            for url in urls { petController.importPetPack(at: url) }
        } else {
            pendingPetPacks.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

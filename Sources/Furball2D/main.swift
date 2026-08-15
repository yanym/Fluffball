import AppKit

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
            let controller = try PetController(startingPosture: .sleep)
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
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

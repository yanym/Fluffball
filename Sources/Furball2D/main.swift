import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

import AppKit

/// Plans lightweight, spatial interactions with familiar desktop landmarks.
/// Reading icon names is local and non-destructive. Finder icon movement is a
/// separate opt-in operation because it changes the user's desktop layout.
struct DesktopInteractionService {
    struct Destination {
        enum Kind {
            case trash
            case desktopItem
        }

        let kind: Kind
        let point: NSPoint
        let itemName: String?
        let itemURL: URL?
    }

    func destination(in screen: NSScreen) -> Destination? {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let desktopItems = desktopItems()

        if !desktopItems.isEmpty, Bool.random() {
            let index = Int.random(in: 0..<min(12, desktopItems.count))
            let row = index % 7
            let column = index / 7
            let point = NSPoint(
                x: frame.maxX - 74 - CGFloat(column * 92),
                y: frame.maxY - 76 - CGFloat(row * 82)
            )
            let item = desktopItems[index]
            return Destination(kind: .desktopItem, point: point, itemName: item.lastPathComponent, itemURL: item)
        }

        // Infer the Dock edge from the difference between frame and visibleFrame.
        // The Trash is at the terminal end of the Dock; this stays useful even
        // when Finder automation permission has not been granted.
        let bottomInset = visible.minY - frame.minY
        let leftInset = visible.minX - frame.minX
        let rightInset = frame.maxX - visible.maxX
        let trashPoint: NSPoint
        if bottomInset >= max(leftInset, rightInset), bottomInset > 4 {
            trashPoint = NSPoint(x: frame.maxX - 34, y: frame.minY + max(28, bottomInset / 2))
        } else if leftInset > rightInset {
            trashPoint = NSPoint(x: frame.minX + max(28, leftInset / 2), y: frame.minY + 34)
        } else {
            trashPoint = NSPoint(x: frame.maxX - max(28, rightInset / 2), y: frame.minY + 34)
        }
        return Destination(kind: .trash, point: trashPoint, itemName: nil, itemURL: nil)
    }

    func nudgeDesktopItem(named name: String, from appKitPoint: NSPoint, in screen: NSScreen) -> Bool {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let finderX = Int(appKitPoint.x - screen.frame.minX + 46)
        let finderY = Int(screen.frame.maxY - appKitPoint.y + 24)
        let source = """
        tell application "Finder"
            set matches to every item of desktop whose name is "\(escaped)"
            if (count of matches) is 0 then return "missing"
            set desktop position of item 1 of matches to {\(finderX), \(finderY)}
            return "moved"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.stringValue == "moved"
    }

    private func desktopItems() -> [URL] {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: desktop,
                includingPropertiesForKeys: [.isHiddenKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

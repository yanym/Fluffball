import AppKit

/// Plans lightweight, spatial interactions with familiar desktop landmarks.
///
/// Safety invariant: this service is read-only. It may enumerate visible item
/// names and ask AppKit for icons, but it never tells Finder to move an item and
/// never writes, renames, trashes, or deletes a file or folder. The pet carries
/// an app-owned visual proxy while the real desktop item remains untouched.
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
        if Bool.random(), let item = desktopItemDestination(in: screen) { return item }
        return trashDestination(in: screen)
    }

    func desktopItemDestination(in screen: NSScreen) -> Destination? {
        let items = desktopItems()
        guard !items.isEmpty else { return nil }
        let index = Int.random(in: 0..<min(12, items.count))
        let row = index % 7
        let column = index / 7
        let point = NSPoint(
            x: screen.frame.maxX - 74 - CGFloat(column * 92),
            y: screen.frame.maxY - 76 - CGFloat(row * 82)
        )
        let item = items[index]
        return Destination(
            kind: .desktopItem,
            point: point,
            itemName: item.lastPathComponent,
            itemURL: item
        )
    }

    func trashDestination(in screen: NSScreen) -> Destination {
        let frame = screen.frame
        let visible = screen.visibleFrame

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

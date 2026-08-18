import AppKit

@MainActor
enum VisualQACapture {
    static func schedule(view: NSView?, name: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        guard let view,
              let directory = ProcessInfo.processInfo.environment["FURBALL_QA_CAPTURE_DIR"],
              !directory.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            view.window?.displayIfNeeded()
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            view.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? data.write(to: root.appendingPathComponent("\(name).png"), options: .atomic)
        }
    }
}

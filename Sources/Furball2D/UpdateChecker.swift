import AppKit

struct FurballRelease: Equatable, Sendable {
    let version: String
    let tagName: String
    let pageURL: URL
    let downloadURL: URL
}

enum FurballUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(FurballRelease)
    case failed(message: String)
}

extension Notification.Name {
    static let furballUpdateStateDidChange = Notification.Name("furballUpdateStateDidChange")
}

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private enum PreferenceKey {
        static let lastPromptedRelease = "lastPromptedGitHubRelease"
    }

    // The product was renamed to Furball, while the existing public release
    // channel intentionally remains at the original Fluffball repository URL.
    private let endpoint = URL(string: "https://api.github.com/repos/yanym/Fluffball/releases/latest")!
    private(set) var state: FurballUpdateState = .idle {
        didSet {
            NotificationCenter.default.post(name: .furballUpdateStateDidChange, object: self)
        }
    }
    private var task: Task<Void, Never>?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.3"
    }

    var availableRelease: FurballRelease? {
        guard case .available(let release) = state else { return nil }
        return release
    }

    func checkAutomatically() {
        check(manual: false, presenting: nil)
    }

    func checkManually(presenting window: NSWindow?) {
        if let release = availableRelease {
            presentAvailableUpdate(release, presenting: window, rememberPrompt: false)
            return
        }
        check(manual: true, presenting: window)
    }

    func openAvailableRelease() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.downloadURL)
    }

    private func check(manual: Bool, presenting window: NSWindow?) {
        guard task == nil else { return }
        state = .checking
        task = Task { [weak self, weak window] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 12
                request.cachePolicy = .reloadRevalidatingCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("Furball/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let githubRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let remoteVersion = Self.normalizedVersion(githubRelease.tagName)
                if Self.isVersion(remoteVersion, newerThan: currentVersion) {
                    let preferredAsset = githubRelease.assets.first(where: {
                        $0.name.lowercased().hasSuffix(".dmg")
                    }) ?? githubRelease.assets.first(where: {
                        $0.name.lowercased().hasSuffix(".zip")
                    })
                    let release = FurballRelease(
                        version: remoteVersion,
                        tagName: githubRelease.tagName,
                        pageURL: githubRelease.htmlURL,
                        downloadURL: preferredAsset?.browserDownloadURL ?? githubRelease.htmlURL
                    )
                    state = .available(release)
                    let alreadyPrompted = UserDefaults.standard.string(
                        forKey: PreferenceKey.lastPromptedRelease
                    ) == release.tagName
                    if manual || !alreadyPrompted {
                        presentAvailableUpdate(
                            release,
                            presenting: window,
                            rememberPrompt: !manual
                        )
                    }
                } else {
                    state = .upToDate(currentVersion: currentVersion)
                    if manual { presentUpToDate(presenting: window) }
                }
            } catch {
                state = .failed(message: error.localizedDescription)
                if manual { presentFailure(error, presenting: window) }
            }
        }
    }

    private func presentAvailableUpdate(
        _ release: FurballRelease,
        presenting window: NSWindow?,
        rememberPrompt: Bool
    ) {
        if rememberPrompt {
            UserDefaults.standard.set(release.tagName, forKey: PreferenceKey.lastPromptedRelease)
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "pawprint.circle.fill", accessibilityDescription: nil)
        alert.messageText = "A fresh Furball is ready ✨"
        alert.informativeText = "Version \(release.version) is available. You have \(currentVersion). Download it from the official GitHub release."
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")
        present(alert, on: window) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.downloadURL)
            }
        }
    }

    private func presentUpToDate(presenting window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: nil)
        alert.messageText = "Furball is up to date"
        alert.informativeText = "You’re running the newest public release (\(currentVersion))."
        alert.addButton(withTitle: "Lovely")
        present(alert, on: window, completion: { _ in })
    }

    private func presentFailure(_ error: Error, presenting window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t check for updates"
        alert.informativeText = "Please try again later. \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        present(alert, on: window, completion: { _ in })
    }

    private func present(
        _ alert: NSAlert,
        on window: NSWindow?,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    static func normalizedVersion(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

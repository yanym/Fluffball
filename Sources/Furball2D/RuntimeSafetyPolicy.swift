import Foundation

/// Product-level safety boundary for the shipping desktop pet.
///
/// Furball may read bundled assets, preferences, and desktop item metadata. It
/// must never mutate Desktop items, Finder preferences, or Finder icon positions.
/// A user-invoked Pet Pack import may write only below Furball's private managed
/// Application Support library, after validation and a strict path check.
enum RuntimeSafetyPolicy {
    static let permitsUserFileMutations = false

    static var permitsDeveloperQAFileWrites: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    static func requireUserFileMutationPermission() throws {
        guard permitsUserFileMutations else {
            throw PetPackLibraryError.readOnlyRuntime
        }
    }

    static func requireManagedPetLibraryURL(_ url: URL) throws {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let library = PetAssetCatalog.userPetPacksDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = library.path.hasSuffix("/") ? library.path : library.path + "/"
        guard candidate.path.hasPrefix(prefix), candidate.path != library.path else {
            throw PetPackLibraryError.operationFailed("The Pet Pack destination is outside Furball's managed library.")
        }
    }
}

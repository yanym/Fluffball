import Foundation

/// Product-level safety boundary for the shipping desktop pet.
///
/// Furball may read bundled assets, preferences, and desktop item metadata. It
/// must never mutate user files, folders, Finder preferences, or Finder icon
/// positions. Asset production and packaging remain developer-side scripts and
/// are deliberately outside the running application.
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
}

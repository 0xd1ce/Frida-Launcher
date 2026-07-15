import Foundation

// MARK: - Domain models (mirror the Android `FridaRelease` / `FridaAsset` data classes)

struct FridaAsset: Identifiable, Hashable {
    let name: String
    let downloadURL: String
    let architecture: String
    let size: Int64
    var id: String { name }
}

struct FridaRelease: Identifiable, Hashable {
    let version: String
    let releaseDate: String
    let assets: [FridaAsset]
    /// True only for the version Frida's repo currently hosts (the latest). Older versions
    /// appear in the list for reference but can't be installed from the official repo.
    let isAvailable: Bool
    var id: String { version }
}

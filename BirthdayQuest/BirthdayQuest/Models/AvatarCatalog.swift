import Foundation

/// The bundled avatar set. Everything renders from the asset catalog — there is no network
/// path, which is deliberate: the previous implementation sent every unrecognised display
/// name to a third-party image API on each render.
enum AvatarCatalog {
    static let all: [String] = ["01", "02", "03", "04", "05"]

    static let fallback = "01"

    static func assetName(for avatarId: String) -> String {
        let id = all.contains(avatarId) ? avatarId : fallback
        return "avatar-\(id)"
    }

    /// Deterministically maps a display name onto the catalog so the same name always
    /// resolves to the same avatar, across launches and devices. Swift's `hashValue` is
    /// seeded per-process and would pick a different avatar every launch, so this uses an
    /// explicit FNV-1a hash over the name's UTF-8 bytes instead.
    static func avatarId(forName name: String) -> String {
        let hash = fnv1aHash(name)
        let index = Int(hash % UInt64(all.count))
        return all[index]
    }

    private static func fnv1aHash(_ string: String) -> UInt64 {
        let prime: UInt64 = 0x100_0000_01b3
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash.multipliedReportingOverflow(by: prime).partialValue
        }
        return hash
    }
}

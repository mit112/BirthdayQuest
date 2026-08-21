import Testing
import UIKit
@testable import BirthdayQuest

@Suite("Avatar catalog")
struct AvatarCatalogTests {

    @Test("every catalog id maps to a bundled asset name")
    func assetNames() {
        for id in AvatarCatalog.all {
            #expect(AvatarCatalog.assetName(for: id).hasPrefix("avatar-"))
        }
    }

    @Test("an unknown id falls back to a bundled asset, never a network call")
    func unknownIdFallsBack() {
        let name = AvatarCatalog.assetName(for: "not-a-real-avatar")
        #expect(AvatarCatalog.all.contains { AvatarCatalog.assetName(for: $0) == name })
    }

    @Test("the catalog is not empty and has no duplicates")
    func catalogShape() {
        #expect(!AvatarCatalog.all.isEmpty)
        #expect(Set(AvatarCatalog.all).count == AvatarCatalog.all.count)
    }

    @Test("every catalog id resolves to a real bundled image, not a blank circle")
    func everyIdResolvesToABundledImage() {
        for id in AvatarCatalog.all {
            let assetName = AvatarCatalog.assetName(for: id)
            #expect(UIImage(named: assetName) != nil, "no bundled image for \(assetName)")
        }
    }

    @Test("mapping a name to an avatar is stable across repeated calls")
    func nameMappingIsStable() {
        let first = AvatarCatalog.avatarId(forName: "Priya Patel")
        let second = AvatarCatalog.avatarId(forName: "Priya Patel")
        #expect(first == second)
        #expect(AvatarCatalog.all.contains(first))
    }
}

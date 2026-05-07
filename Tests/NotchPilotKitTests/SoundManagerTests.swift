import XCTest

@testable import NotchPilotKit

final class SoundManagerPickTests: XCTestCase {
    @MainActor
    func testPickURLReturnsTheLoneEntryWhenOnlyOne() {
        let manager = makeIsolatedManager()
        let only = URL(fileURLWithPath: "/tmp/a.wav")
        XCTAssertEqual(manager.pickURL(from: [only], category: .taskComplete), only)
    }

    @MainActor
    func testPickURLAvoidsRepeatingTheLastPlayed() {
        let manager = makeIsolatedManager()
        let a = URL(fileURLWithPath: "/tmp/a.wav")
        let b = URL(fileURLWithPath: "/tmp/b.wav")

        // After "playing" a, the next pick from {a, b} must be b.
        manager.recordLastPlayedForTest(url: a, category: .taskComplete)
        XCTAssertEqual(manager.pickURL(from: [a, b], category: .taskComplete), b)
    }

    @MainActor
    func testPickURLFallsBackWhenAllCandidatesEqualLast() {
        let manager = makeIsolatedManager()
        let a = URL(fileURLWithPath: "/tmp/a.wav")
        manager.recordLastPlayedForTest(url: a, category: .inputRequired)

        // Only one URL exists and it equals last — must still return it
        // instead of returning nil.
        XCTAssertEqual(manager.pickURL(from: [a], category: .inputRequired), a)
    }

    // MARK: - Helpers

    @MainActor
    private func makeIsolatedManager() -> SoundManager {
        // Bundle lookup that returns nil so the built-in pack can't bleed into
        // tests if the resource happens to exist.
        SoundManager(
            loader: SoundPackLoader(),
            store: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            bundleLookup: { nil }
        )
    }
}

extension SoundManager {
    /// Test-only seam for the `lastPlayedURL` cache so we don't have to
    /// trigger real audio playback to verify the no-repeat contract.
    func recordLastPlayedForTest(url: URL, category: CESPCategory) {
        // Reach into private storage via a public path: pickURL records the
        // chosen URL in the cache, so we can prime the cache by playing-then-
        // discarding through it. This requires only a single entry, so we
        // call pickURL with that one URL to make it the recorded last.
        _ = pickURL(from: [url], category: category)
    }
}

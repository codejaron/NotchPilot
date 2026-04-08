import XCTest
@testable import NotchPilotKit

final class CodexDesktopModelsTests: XCTestCase {
    func testMergedSurfacePrefersContextTitleWhenSurfaceTitleLooksLikeUUID() {
        let surface = CodexActionableSurface(
            id: "surface-1",
            summary: "Run command?",
            primaryButtonTitle: "Submit",
            cancelButtonTitle: "Skip",
            threadID: "019d6aff-09ea-70c0-8cb4-efbd0565ce68",
            threadTitle: "019d6aff-09ea-70c0-8cb4-efbd0565ce68"
        )
        let context = CodexThreadContext(
            threadID: "019d6aff-09ea-70c0-8cb4-efbd0565ce68",
            title: "Codex Desktop Approval",
            activityLabel: "Working",
            phase: .working
        )

        let merged = surface.merged(with: context)

        XCTAssertEqual(merged.threadTitle, "Codex Desktop Approval")
    }
}

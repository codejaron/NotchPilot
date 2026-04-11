import AppKit
import XCTest

final class BrandIconResourceTests: XCTestCase {
    func testCodexIconUsesTransparentIrregularLogoWithWhiteGlyph() throws {
        let iconURL = packageRoot()
            .appendingPathComponent("Sources/NotchPilotKit/Resources/Icons/codex-color.svg")
        let svg = try String(contentsOf: iconURL, encoding: .utf8)

        XCTAssertTrue(svg.contains("M 9.064 3.344"), "Codex logo should keep the irregular brand shape.")
        XCTAssertTrue(svg.contains("a 4.578 4.578 0 0 1"), "Codex path should stay compatible with CoreSVG.")
        XCTAssertFalse(svg.contains("M19.503 0H4.496"), "Codex logo should not use the rounded-square app icon base.")
        XCTAssertFalse(svg.contains("<rect"), "Codex logo should not include a background rectangle.")
        XCTAssertEqual(svg.components(separatedBy: "fill=\"#fff\"").count - 1, 2, "Only the arrow and dash should be white.")

        let image = try XCTUnwrap(NSImage(contentsOf: iconURL))
        XCTAssertEqual(image.size.width, 24)
        XCTAssertEqual(image.size.height, 24)
        XCTAssertFalse(image.isTemplate)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

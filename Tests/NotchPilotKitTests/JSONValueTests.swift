import XCTest
@testable import NotchPilotKit

final class JSONValueTests: XCTestCase {
    func testIntegerValueRejectsNonFiniteDouble() {
        XCTAssertNil(JSONValue.double(.nan).integerValue)
        XCTAssertNil(JSONValue.double(.infinity).integerValue)
    }

    func testIntegerValueRejectsOutOfRangeDouble() {
        XCTAssertNil(JSONValue.double(Double.greatestFiniteMagnitude).integerValue)
    }
}

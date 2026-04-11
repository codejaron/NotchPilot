import SwiftUI
import XCTest
@testable import NotchPilotKit

final class NotchShapeTests: XCTestCase {
    func testShapeStartsWithConcaveTopCornersLikeDynamicIsland() {
        let path = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .path(in: CGRect(x: 0, y: 0, width: 200, height: 32))
            .cgPath
            .elements()

        guard case let .move(start) = path.first else {
            return XCTFail("expected path to start with a move")
        }
        guard path.count > 1, case let .quadCurve(to, control) = path[1] else {
            return XCTFail("expected the first drawn segment to be a top concave curve")
        }

        XCTAssertEqual(start.x, 0, accuracy: 0.1)
        XCTAssertEqual(start.y, 0, accuracy: 0.1)
        XCTAssertEqual(to.x, 6, accuracy: 0.1)
        XCTAssertEqual(to.y, 6, accuracy: 0.1)
        XCTAssertEqual(control.x, 6, accuracy: 0.1)
        XCTAssertEqual(control.y, 0, accuracy: 0.1)
    }
}

private enum TestPathElement {
    case move(CGPoint)
    case line(CGPoint)
    case quadCurve(CGPoint, CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)
    case close
}

private extension CGPath {
    func elements() -> [TestPathElement] {
        var result: [TestPathElement] = []
        applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                result.append(.move(element.points[0]))
            case .addLineToPoint:
                result.append(.line(element.points[0]))
            case .addQuadCurveToPoint:
                result.append(.quadCurve(element.points[1], element.points[0]))
            case .addCurveToPoint:
                result.append(.curve(element.points[2], element.points[0], element.points[1]))
            case .closeSubpath:
                result.append(.close)
            @unknown default:
                break
            }
        }
        return result
    }
}

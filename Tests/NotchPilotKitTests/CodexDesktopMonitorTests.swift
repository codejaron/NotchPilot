import XCTest
@testable import NotchPilotKit

final class CodexDesktopMonitorTests: XCTestCase {
    func testCanHandleDiscoveryRequestOnlyForApprovalMethods() {
        let approvalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1",
            method: "item/commandExecution/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let nonApprovalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-2",
            method: "ide-context",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )

        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(approvalRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nonApprovalRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nil))
    }
}

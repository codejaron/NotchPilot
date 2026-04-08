import XCTest
@testable import NotchPilotKit

final class CodexDesktopMonitorTests: XCTestCase {
    func testCanHandleDiscoveryRequestRecognizesSupportedApprovalRequests() {
        let approvalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1",
            method: "item/commandExecution/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let fileChangeRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1b",
            method: "item/fileChange/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyExecRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1legacy",
            method: "execCommandApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyPatchRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1patch",
            method: "applyPatchApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let permissionsRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1c",
            method: "item/permissions/requestApproval",
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
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(fileChangeRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyExecRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyPatchRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(permissionsRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nonApprovalRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nil))
    }
}

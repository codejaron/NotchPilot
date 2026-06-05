import XCTest
@testable import NotchPilotKit

final class CodexSessionQuotaRefreshSchedulerTests: XCTestCase {
    func testPollingRefreshesImmediatelyWhenEnabled() async {
        let scheduler = CodexSessionQuotaRefreshScheduler(
            pollingRefreshInterval: 0.2
        )
        let refreshRequested = expectation(description: "polling requested refresh immediately")

        scheduler.activate { preferredFileURL in
            XCTAssertNil(preferredFileURL)
            refreshRequested.fulfill()
        }
        scheduler.setPollingEnabled(true)

        await fulfillment(of: [refreshRequested], timeout: 0.05)
        scheduler.deactivate()
    }
}

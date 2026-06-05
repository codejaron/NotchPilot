import XCTest
@testable import NotchPilotKit

final class CodexUsageQuotaRefreshSchedulerTests: XCTestCase {
    func testPollingRefreshesImmediatelyWhenEnabled() async {
        let scheduler = CodexUsageQuotaRefreshScheduler(
            pollingRefreshInterval: 0.2
        )
        let refreshRequested = expectation(description: "polling requested refresh immediately")

        scheduler.activate {
            refreshRequested.fulfill()
        }
        scheduler.setPollingEnabled(true)

        await fulfillment(of: [refreshRequested], timeout: 0.05)
        scheduler.deactivate()
    }
}

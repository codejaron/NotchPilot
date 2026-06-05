import Foundation
import XCTest
@testable import NotchPilotKit

final class CodexAccountUsageQuotaReaderTests: XCTestCase {
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHomeURL)
        tempHomeURL = nil
    }

    func testAccountReaderUsesCodexAuthForWhamUsageRequest() async throws {
        try writeAuth(accessToken: "test-access-token", accountID: "account-123")
        let httpClient = FakeCodexAccountUsageHTTPClient(response: .success(
            statusCode: 200,
            body: """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 20,
                  "limit_window_seconds": 18000,
                  "reset_at": 1780302427
                },
                "secondary_window": {
                  "used_percent": 30,
                  "limit_window_seconds": 604800,
                  "reset_at": 1780889227
                }
              }
            }
            """
        ))
        let reader = CodexAccountUsageQuotaReader(
            homeDirectoryURL: tempHomeURL,
            httpClient: httpClient
        )

        let snapshot = await reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0))

        let maybeRequest = await httpClient.firstRequest()
        let request = try XCTUnwrap(maybeRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(snapshot?.source, .codexAccountUsage)
        XCTAssertEqual(snapshot?.window(.fiveHour)?.remainingPercent, 80)
        XCTAssertEqual(snapshot?.window(.sevenDay)?.remainingPercent, 70)
    }

    func testAccountReaderReturnsNilWhenUsageEndpointIsUnavailable() async throws {
        try writeAuth(accessToken: "test-access-token", accountID: "account-123")
        let reader = CodexAccountUsageQuotaReader(
            homeDirectoryURL: tempHomeURL,
            httpClient: FakeCodexAccountUsageHTTPClient(response: .success(statusCode: 401, body: #"{"error":"unauthorized"}"#))
        )

        let snapshot = await reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0))

        XCTAssertNil(snapshot)
    }

    private func writeAuth(accessToken: String, accountID: String) throws {
        let url = tempHomeURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(accessToken)",
            "account_id": "\(accountID)",
            "refresh_token": "test-refresh-token",
            "id_token": "test-id-token"
          }
        }
        """.write(to: url, atomically: true, encoding: .utf8)
    }

}

private actor FakeCodexAccountUsageHTTPClient: CodexAccountUsageHTTPClient {
    enum Response {
        case success(statusCode: Int, body: String)
        case failure
    }

    private(set) var requests: [URLRequest] = []
    private let response: Response

    init(response: Response) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> CodexAccountUsageHTTPResponse {
        requests.append(request)
        switch response {
        case let .success(statusCode, body):
            return CodexAccountUsageHTTPResponse(
                statusCode: statusCode,
                data: Data(body.utf8)
            )
        case .failure:
            throw URLError(.badServerResponse)
        }
    }

    func firstRequest() -> URLRequest? {
        requests.first
    }
}

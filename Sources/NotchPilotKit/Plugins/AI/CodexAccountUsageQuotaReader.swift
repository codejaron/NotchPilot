import Foundation

struct CodexAccountUsageHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol CodexAccountUsageHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> CodexAccountUsageHTTPResponse
}

protocol CodexUsageQuotaReading: Sendable {
    func latestSnapshot(collectedAt: Date) async -> AIUsageQuotaSnapshot?
}

struct CodexURLSessionAccountUsageHTTPClient: CodexAccountUsageHTTPClient {
    func data(for request: URLRequest) async throws -> CodexAccountUsageHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return CodexAccountUsageHTTPResponse(statusCode: -1, data: data)
        }

        return CodexAccountUsageHTTPResponse(
            statusCode: httpResponse.statusCode,
            data: data
        )
    }
}

actor CodexAccountUsageQuotaReader: CodexUsageQuotaReading {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountID: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountID = "account_id"
            }
        }

        let tokens: Tokens?
    }

    private struct AuthCredentials: Sendable {
        let accessToken: String
        let accountID: String?
    }

    private static let defaultEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let authFileURL: URL
    private let endpointURL: URL
    private let httpClient: any CodexAccountUsageHTTPClient

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        endpointURL: URL = CodexAccountUsageQuotaReader.defaultEndpointURL,
        httpClient: any CodexAccountUsageHTTPClient = CodexURLSessionAccountUsageHTTPClient()
    ) {
        self.authFileURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
        self.endpointURL = endpointURL
        self.httpClient = httpClient
    }

    func latestSnapshot(collectedAt: Date) async -> AIUsageQuotaSnapshot? {
        guard let credentials = authCredentials() else {
            return nil
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        guard let response = try? await httpClient.data(for: request),
              (200..<300).contains(response.statusCode)
        else {
            return nil
        }

        let rawJSON = String(decoding: response.data, as: UTF8.self)
        return AIUsageQuotaSnapshot.codexAccountUsage(rawJSON: rawJSON, collectedAt: collectedAt)
    }

    private func authCredentials() -> AuthCredentials? {
        guard let data = try? Data(contentsOf: authFileURL),
              let authFile = try? JSONDecoder().decode(AuthFile.self, from: data),
              let accessToken = trimmedNonEmpty(authFile.tokens?.accessToken)
        else {
            return nil
        }

        return AuthCredentials(
            accessToken: accessToken,
            accountID: trimmedNonEmpty(authFile.tokens?.accountID)
        )
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

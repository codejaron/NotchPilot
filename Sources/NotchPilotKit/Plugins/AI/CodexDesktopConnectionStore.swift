import Combine
import Foundation

@MainActor
public final class CodexDesktopConnectionStore: ObservableObject {
    public static let shared = CodexDesktopConnectionStore()

    @Published public private(set) var connection: CodexDesktopConnectionState

    public init(initialConnection: CodexDesktopConnectionState = .notFound) {
        self.connection = initialConnection
    }

    public func update(_ state: CodexDesktopConnectionState) {
        connection = state
    }

    public func synchronizeInstallationState(isDetected: Bool) {
        if isDetected == false {
            connection = .notFound
        } else if connection.status == .notFound {
            connection = .disconnected
        }
    }
}

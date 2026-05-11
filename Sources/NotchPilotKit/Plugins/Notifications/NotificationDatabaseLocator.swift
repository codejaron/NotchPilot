import Foundation

public protocol NotificationDatabaseLocatorFileSystem {
    func fileExists(atPath path: String) -> Bool
}

extension FileManager: NotificationDatabaseLocatorFileSystem {}

public struct NotificationDatabaseLocator {
    private let fileSystem: NotificationDatabaseLocatorFileSystem
    private let homeDirectoryURL: URL

    public init(
        fileSystem: NotificationDatabaseLocatorFileSystem = FileManager.default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileSystem = fileSystem
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func locateDatabase() -> URL? {
        let candidates = [
            homeDirectoryURL
                .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db"),
            homeDirectoryURL
                .appendingPathComponent("Library/Application Support/NotificationCenter/db2/db"),
        ]
        return candidates.first(where: { fileSystem.fileExists(atPath: $0.path) })
    }
}

import AppKit
import Foundation

@MainActor
public protocol NotificationAppDirectoryWorkspace {
    func appURL(forBundleIdentifier id: String) -> URL?
    func appName(forBundleIdentifier id: String) -> String?
}

public struct SystemNotificationAppWorkspace: NotificationAppDirectoryWorkspace {
    public init() {}

    @MainActor
    public func appURL(forBundleIdentifier id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    @MainActor
    public func appName(forBundleIdentifier id: String) -> String? {
        guard let url = appURL(forBundleIdentifier: id) else { return nil }
        // Prefer the app bundle's own display name; fall back to filename without .app suffix.
        if let info = Bundle(url: url)?.infoDictionary {
            if let displayName = info["CFBundleDisplayName"] as? String,
               displayName.isEmpty == false {
                return displayName
            }
            if let bundleName = info["CFBundleName"] as? String,
               bundleName.isEmpty == false {
                return bundleName
            }
        }
        let raw = FileManager.default.displayName(atPath: url.path)
        if raw.hasSuffix(".app") {
            return String(raw.dropLast(4))
        }
        return raw
    }
}

@MainActor
public final class NotificationAppDirectory {
    public struct AppMeta: Equatable, Sendable {
        public let bundleIdentifier: String
        public let displayName: String
        public let appURL: URL
    }

    private let workspace: NotificationAppDirectoryWorkspace
    private var cache: [String: AppMeta?] = [:]

    public init(workspace: NotificationAppDirectoryWorkspace = SystemNotificationAppWorkspace()) {
        self.workspace = workspace
    }

    public func resolve(bundleIdentifier: String) -> AppMeta? {
        if let cached = cache[bundleIdentifier] {
            return cached
        }
        guard let url = workspace.appURL(forBundleIdentifier: bundleIdentifier) else {
            cache[bundleIdentifier] = .some(nil)
            return nil
        }
        let name = workspace.appName(forBundleIdentifier: bundleIdentifier) ?? bundleIdentifier
        let meta = AppMeta(bundleIdentifier: bundleIdentifier, displayName: name, appURL: url)
        cache[bundleIdentifier] = .some(meta)
        return meta
    }
}

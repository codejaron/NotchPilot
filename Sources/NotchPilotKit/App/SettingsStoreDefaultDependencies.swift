import Foundation

enum SettingsStoreDefaultDependencies {
    static func makeCodexInstallationDetector(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> any CodexInstallationDetecting {
        CodexDesktopAppDetector(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
    }

    static func makeClaudeHookInspector(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> any ClaudeHookInstallationInspecting {
        HookInstaller(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
    }
}

extension CodexDesktopAppDetector: CodexInstallationDetecting {
    public func isCodexInstalled() -> Bool {
        isInstalled()
    }
}

extension HookInstaller: ClaudeHookInstallationInspecting {}

import SwiftUI

struct AIHooksSettingsTab: View {
    @ObservedObject private var store = SettingsStore.shared

    @State private var claudeError: String?
    @State private var codexError: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Agent Hooks")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("Install hooks to let NotchPilot receive events from your AI coding tools.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()

            hookCard(
                icon: "sparkles",
                iconColor: .orange,
                title: "Claude Code",
                subtitle: "PermissionRequest + PreToolUse + PostToolUse + Session hooks",
                detected: store.claudeCodeDetected,
                installed: store.claudeHookInstalled,
                error: claudeError,
                capabilities: [
                    ("checkmark.circle.fill", "Allow / Deny / Always Allow", true),
                    ("checkmark.circle.fill", "Session monitoring", true),
                    ("checkmark.circle.fill", "Token usage tracking", true),
                ],
                installAction: installClaude,
                uninstallAction: uninstallClaude
            )

            hookCard(
                icon: "terminal",
                iconColor: .blue,
                title: "OpenAI Codex",
                subtitle: "PreToolUse (deny only) + PostToolUse + Session hooks",
                detected: store.codexDetected,
                installed: store.codexHookInstalled,
                error: codexError,
                capabilities: [
                    ("xmark.circle", "Allow (not supported by Codex yet)", false),
                    ("checkmark.circle.fill", "Deny commands", true),
                    ("checkmark.circle.fill", "Session monitoring", true),
                ],
                installAction: installCodex,
                uninstallAction: uninstallCodex
            )

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(store.autoStartSocket ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text("Bridge socket: /tmp/notchpilot.sock")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("Auto-start", isOn: $store.autoStartSocket)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshInstallationState)
    }

    private func hookCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        detected: Bool,
        installed: Bool,
        error: String?,
        capabilities: [(String, String, Bool)],
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        statusBadge(detected: detected, installed: installed)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if detected {
                    if installed {
                        Button("Uninstall") { uninstallAction() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isWorking)
                    } else {
                        Button("Install Hooks") { installAction() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isWorking)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(capabilities.indices, id: \.self) { index in
                    let capability = capabilities[index]
                    HStack(spacing: 6) {
                        Image(systemName: capability.0)
                            .font(.system(size: 11))
                            .foregroundStyle(capability.2 ? .green : .gray)

                        Text(capability.1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(capability.2 ? .primary : .secondary)
                    }
                }
            }
            .padding(.leading, 26)

            if let error {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.leading, 26)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func statusBadge(detected: Bool, installed: Bool) -> some View {
        Group {
            if detected == false {
                badge("Not found", fill: Color.gray.opacity(0.3), foreground: Color.primary)
            } else if installed {
                badge("Connected", fill: Color.green.opacity(0.25), foreground: .green)
            } else {
                badge("Not configured", fill: Color.orange.opacity(0.25), foreground: .orange)
            }
        }
    }

    private func badge(_ text: String, fill: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
            .foregroundStyle(foreground)
    }

    private func installClaude() {
        claudeError = nil
        codexError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = try ensureBridgeScript()
            let installer = HookInstaller()
            try installer.installClaudeHooks(bridgeScript: bridgePath)
            store.bridgeScriptPath = bridgePath
            store.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func uninstallClaude() {
        claudeError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = store.bridgeScriptPath.isEmpty ? nil : store.bridgeScriptPath
            try HookInstaller().uninstallClaudeHooks(bridgeScript: bridgePath)
            store.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func installCodex() {
        claudeError = nil
        codexError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = try ensureBridgeScript()
            let installer = HookInstaller()
            try installer.installCodexHooks(bridgeScript: bridgePath)
            store.bridgeScriptPath = bridgePath
            store.synchronizeInstallationState()
        } catch {
            codexError = error.localizedDescription
        }
    }

    private func uninstallCodex() {
        codexError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = store.bridgeScriptPath.isEmpty ? nil : store.bridgeScriptPath
            try HookInstaller().uninstallCodexHooks(bridgeScript: bridgePath)
            store.synchronizeInstallationState()
        } catch {
            codexError = error.localizedDescription
        }
    }

    private func ensureBridgeScript() throws -> String {
        if store.bridgeScriptPath.isEmpty == false,
           FileManager.default.fileExists(atPath: store.bridgeScriptPath) {
            return store.bridgeScriptPath
        }

        if let bundledURL = Bundle.module.url(forResource: "notch-bridge", withExtension: "py") {
            let path = try HookInstaller().installBridgeScript(fromBundle: bundledURL.path)
            store.bridgeScriptPath = path
            return path
        }

        let fallbackPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchpilot/notch-bridge.py")
            .path
        guard FileManager.default.fileExists(atPath: fallbackPath) else {
            throw HookInstallError.writeError("Bridge script not found. Place notch-bridge.py in ~/.notchpilot/")
        }

        store.bridgeScriptPath = fallbackPath
        return fallbackPath
    }

    private func refreshInstallationState() {
        store.synchronizeInstallationState()
    }
}

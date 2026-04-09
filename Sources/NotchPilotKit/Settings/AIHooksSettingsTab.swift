import SwiftUI

struct AIHooksSettingsTab: View {
    @ObservedObject private var store = SettingsStore.shared

    @State private var claudeError: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Integrations")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("Claude uses hooks. Codex uses desktop IPC for context, approvals, and session activity.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()

            hookCard(
                icon: "sparkles",
                iconColor: .orange,
                title: "Claude Code",
                subtitle: "PermissionRequest + PreToolUse + PostToolUse + Session + Prompt hooks",
                detected: store.claudeCodeDetected,
                installed: store.claudeHookInstalled,
                needsUpdate: store.claudeHooksNeedUpdate,
                error: claudeError,
                capabilities: [
                    ("checkmark.circle.fill", "Allow / Deny / Always Allow", true),
                    ("checkmark.circle.fill", "Session monitoring", true),
                    ("checkmark.circle.fill", "Token usage tracking", true),
                ],
                installAction: installClaude,
                uninstallAction: uninstallClaude
            )

            codexDesktopCard(
                icon: "terminal",
                iconColor: .blue,
                title: "OpenAI Codex",
                subtitle: "Desktop IPC context + approval actions",
                detected: store.codexDetected,
                connection: store.codexDesktopConnection,
                capabilities: [
                    ("checkmark.circle.fill", "Context monitoring via IPC", store.codexDesktopConnection.status == .connected),
                    ("checkmark.circle.fill", "Approval actions via IPC", store.codexDesktopConnection.status == .connected),
                    ("checkmark.circle.fill", "Session monitoring", true),
                ]
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
        needsUpdate: Bool,
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

                        statusBadge(detected: detected, installed: installed, needsUpdate: needsUpdate)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if detected {
                    if installed && needsUpdate {
                        Button("Update Hooks") { installAction() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isWorking)
                    } else if installed {
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

    private func codexDesktopCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        detected: Bool,
        connection: CodexDesktopConnectionState,
        capabilities: [(String, String, Bool)]
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

                        codexStatusBadge(detected: detected, connection: connection)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
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

            if let message = connection.message, message.isEmpty == false {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(connection.status == .error ? .red : .secondary)
                    .padding(.leading, 26)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func statusBadge(detected: Bool, installed: Bool, needsUpdate: Bool) -> some View {
        Group {
            if detected == false {
                badge("Not found", fill: Color.gray.opacity(0.3), foreground: Color.primary)
            } else if installed == false {
                badge("Not configured", fill: Color.orange.opacity(0.25), foreground: .orange)
            } else if needsUpdate {
                badge("Update available", fill: Color.yellow.opacity(0.25), foreground: .yellow)
            } else if installed {
                badge("Connected", fill: Color.green.opacity(0.25), foreground: .green)
            }
        }
    }

    private func codexStatusBadge(detected: Bool, connection: CodexDesktopConnectionState) -> some View {
        Group {
            if detected == false || connection.status == .notFound {
                badge("Not found", fill: Color.gray.opacity(0.3), foreground: Color.primary)
            } else {
                switch connection.status {
                case .disconnected:
                    badge("Disconnected", fill: Color.orange.opacity(0.25), foreground: .orange)
                case .connecting:
                    badge("Connecting", fill: Color.yellow.opacity(0.25), foreground: .yellow)
                case .connected:
                    badge("Connected", fill: Color.green.opacity(0.25), foreground: .green)
                case .error:
                    badge("Error", fill: Color.red.opacity(0.2), foreground: .red)
                case .notFound:
                    badge("Not found", fill: Color.gray.opacity(0.3), foreground: Color.primary)
                }
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

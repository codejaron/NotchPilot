import XCTest
@testable import NotchPilotKit

final class CodexPluginTests: XCTestCase {
    private static let previewContext = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

    func testActionableSurfaceDrivesCompactActivityAndSessionSummary() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 5) }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-1",
                    title: "Write plan",
                    activityLabel: "Plan",
                    phase: .plan,
                    inputTokenCount: 120,
                    outputTokenCount: 45
                )
            )
            codexMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-1",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        let summaries = await MainActor.run { plugin.expandedSessionSummaries }

        XCTAssertEqual(activity?.host, .codex)
        XCTAssertEqual(activity?.label, "Action Needed")
        XCTAssertEqual(activity?.approvalCount, 0)
        XCTAssertEqual(activity?.sessionTitle, "Write plan")
        XCTAssertEqual(summaries.first?.inputTokenCount, 120)
        XCTAssertEqual(summaries.first?.outputTokenCount, 45)
        XCTAssertEqual(summaries.first?.approvalCount, 0)
        XCTAssertEqual(summaries.first?.codexSurfaceID, "surface-1")
        XCTAssertEqual(summaries.first?.subtitle, "Action Needed")
    }

    func testActiveThreadEmitsSneakPeekWithoutActionableSurface() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 5) }
            )
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-preview",
                    title: "Preview Thread",
                    activityLabel: "Working",
                    phase: .working,
                    inputTokenCount: 12,
                    outputTokenCount: 3,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        }

        await Task.yield()

        let receivedEvents = await MainActor.run { recorder.events }
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            return XCTFail("expected a sneak peek request")
        }

        XCTAssertEqual(request.pluginID, "codex")

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testConnectedThreadDoesNotEmitSneakPeekWithoutLiveWork() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 5) }
            )
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-connected",
                    title: "Connected Thread",
                    activityLabel: "Connected",
                    phase: .connected,
                    updatedAt: Date(timeIntervalSince1970: 0)
                ),
                marksActivity: false
            )
        }

        await Task.yield()

        let receivedEvents = await MainActor.run { recorder.events }
        XCTAssertTrue(receivedEvents.isEmpty)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testCompletedThreadDismissesActivitySneakPeekAndFallsBackToSystem() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 70) }
            )
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-terminal",
                    title: "Terminal Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-terminal",
                    title: "Terminal Thread",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: Date(timeIntervalSince1970: 10)
                ),
                marksActivity: false
            )
        }

        await Task.yield()

        let receivedEvents = await MainActor.run { recorder.events }
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            return XCTFail("expected initial codex sneak peek request")
        }
        guard case let .dismissSneakPeek(requestID, _)? = receivedEvents.last else {
            return XCTFail("expected codex sneak peek dismissal after completion")
        }

        XCTAssertEqual(request.pluginID, "codex")
        XCTAssertEqual(requestID, request.id)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testCurrentCompactActivityFormatsObservedRunDuration() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 66) }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-runtime",
                    title: "Runtime Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.runtimeDurationText, "1m06s")
    }

    func testCurrentCompactActivityRuntimeDurationDoesNotIntroduceLineBreakSpaces() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { Date(timeIntervalSince1970: 70) }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-runtime",
                    title: "Runtime Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.runtimeDurationText, "1m10s")
    }

    func testCompletedCompactActivityFreezesObservedRunDuration() async {
        let now = MutableDateProvider(Date(timeIntervalSince1970: 120))
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(
                codexMonitor: codexMonitor,
                nowProvider: { now.value }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-runtime",
                    title: "Runtime Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-runtime",
                    title: "Runtime Thread",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: Date(timeIntervalSince1970: 66)
                ),
                marksActivity: false
            )
        }

        now.value = Date(timeIntervalSince1970: 180)

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.runtimeDurationText, "1m06s")
    }

    func testActionableSurfaceEmitsInteractiveSneakPeek() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(codexMonitor: codexMonitor)
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-ipc-peek",
                    summary: "IPC approval",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let receivedEvents = await MainActor.run { recorder.events }
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            return XCTFail("expected a sneak peek request")
        }

        XCTAssertEqual(request.pluginID, "codex")
        XCTAssertEqual(request.priority, 1000)
        XCTAssertTrue(request.isInteractive)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testActionableSurfaceDoesNotEmitSneakPeekWhenApprovalSneakSettingIsDisabled() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let settingsStore = await MainActor.run { makeSettingsStore(approvalSneakNotificationsEnabled: false) }
        let plugin = await MainActor.run {
            CodexPlugin(settingsStore: settingsStore, codexMonitor: codexMonitor)
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-disabled",
                    summary: "Approval hidden",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let receivedEvents = await MainActor.run { recorder.events }
        let hasPreview = await MainActor.run { plugin.preview(context: Self.previewContext) != nil }

        XCTAssertTrue(receivedEvents.isEmpty)
        XCTAssertFalse(hasPreview)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testLongApprovalNoticeExpandsCompactPreviewWidthAndHeight() async {
        let shortMonitor = SplitFakeCodexContextMonitor()
        let longMonitor = SplitFakeCodexContextMonitor()
        let shortPlugin = await MainActor.run {
            CodexPlugin(codexMonitor: shortMonitor)
        }
        let longPlugin = await MainActor.run {
            CodexPlugin(codexMonitor: longMonitor)
        }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            shortPlugin.activate(bus: bus)
            longPlugin.activate(bus: bus)

            shortMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-short",
                    summary: "Run test?",
                    commandPreview: "/bin/zsh -lc 'swift test'",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
            longMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-long",
                    summary: "Do you want me to run the broader notch and system-monitor test subset outside the sandbox to verify the tighter, higher shell layout end to end?",
                    commandPreview: "/bin/zsh -lc 'swift test --filter \"SystemMonitorPluginTests|SystemMonitorModelsTests|NotchLayoutMetricsTests|ScreenSessionModelTests\"'",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let shortPreview = await MainActor.run {
            let preview = shortPlugin.preview(context: Self.previewContext)
            return (preview?.width, preview?.height)
        }
        let longPreview = await MainActor.run {
            let preview = longPlugin.preview(context: Self.previewContext)
            return (preview?.width, preview?.height)
        }

        XCTAssertNotNil(shortPreview.0)
        XCTAssertNotNil(longPreview.0)
        XCTAssertGreaterThan(try XCTUnwrap(longPreview.0), try XCTUnwrap(shortPreview.0))
        XCTAssertGreaterThan(try XCTUnwrap(longPreview.1), try XCTUnwrap(shortPreview.1))
    }

    func testVeryLongApprovalNoticeCanGrowBeyondTwoLines() async {
        let monitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(codexMonitor: monitor)
        }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            monitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-very-long",
                    summary: String(
                        repeating: "Do you want me to run the broader notch and approval verification workflow with the full sneak summary visible? ",
                        count: 5
                    ),
                    commandPreview: "/bin/zsh -lc 'swift test'",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let previewHeight = await MainActor.run {
            plugin.preview(context: Self.previewContext)?.height
        }

        XCTAssertGreaterThan(try XCTUnwrap(previewHeight), Self.previewContext.notchGeometry.compactSize.height + 44)
    }

    func testReenablingApprovalSneakEmitsExistingCodexActionableSurface() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let settingsStore = await MainActor.run { makeSettingsStore(approvalSneakNotificationsEnabled: false) }
        let plugin = await MainActor.run {
            CodexPlugin(settingsStore: settingsStore, codexMonitor: codexMonitor)
        }
        let recorder = await MainActor.run { SplitEventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-reenable",
                    summary: "Need approval",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let initialEvents = await MainActor.run { recorder.events }
        XCTAssertTrue(initialEvents.isEmpty)

        await MainActor.run {
            settingsStore.approvalSneakNotificationsEnabled = true
        }

        let receivedEvents = await MainActor.run { recorder.events }
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            XCTFail("expected a sneak peek request after reenabling codex approval sneak")
            await MainActor.run {
                bus.unsubscribe(token)
            }
            return
        }

        XCTAssertEqual(request.pluginID, "codex")
        XCTAssertTrue(request.isInteractive)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testPerformingCodexPrimaryActionUsesIPCMonitor() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = SplitFakeCodexContextMonitor()
        let plugin = await MainActor.run {
            CodexPlugin(codexMonitor: codexMonitor)
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-ipc-open",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
            _ = plugin.performCodexAction(.primary, surfaceID: "surface-ipc-open")
        }

        let ipcPerformedActions = codexMonitor.performedActions
        let surface = await MainActor.run { plugin.codexActionableSurface }

        XCTAssertEqual(ipcPerformedActions.map(\.0), [.primary])
        XCTAssertEqual(ipcPerformedActions.map(\.1), ["surface-ipc-open"])
        XCTAssertNil(surface)
    }
}

private final class MutableDateProvider: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

@MainActor
private func makeSettingsStore(
    approvalSneakNotificationsEnabled: Bool = true
) -> SettingsStore {
    let suiteName = "CodexPluginTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = SettingsStore(defaults: defaults)
    store.approvalSneakNotificationsEnabled = approvalSneakNotificationsEnabled
    return store
}

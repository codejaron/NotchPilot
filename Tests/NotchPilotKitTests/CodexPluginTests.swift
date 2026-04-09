import XCTest
@testable import NotchPilotKit

final class CodexPluginTests: XCTestCase {
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
        XCTAssertEqual(activity?.approvalCount, 1)
        XCTAssertEqual(activity?.sessionTitle, "Write plan")
        XCTAssertEqual(summaries.first?.inputTokenCount, 120)
        XCTAssertEqual(summaries.first?.outputTokenCount, 45)
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
        XCTAssertEqual(activity?.runtimeDurationText, "1m 6s")
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

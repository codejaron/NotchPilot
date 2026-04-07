import AppKit
import ApplicationServices
import Foundation
import OSLog

public final class CodexDesktopAXMonitor: @unchecked Sendable, CodexDesktopAXMonitoring {
    public var onPermissionStateChanged: (@Sendable (CodexDesktopAXPermissionState) -> Void)?
    public var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)?

    private let logger = Logger(subsystem: "NotchPilot", category: "CodexDesktopAX")
    private let queue = DispatchQueue(label: "NotchPilot.CodexDesktopAXMonitor")
    private let bundleIdentifier: String
    private let pollInterval: TimeInterval
    private let snapshotDepth: Int
    private let webAreaSnapshotDepth: Int
    private let navigationSnapshotDepth: Int
    private let permissionChecker: @Sendable () -> Bool
    private let runningApplicationProvider: @Sendable (String) -> NSRunningApplication?
    private let inspector: CodexDesktopAXInspector
    private let actionResolver: CodexDesktopAXActionResolver

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var lastPermissionState: CodexDesktopAXPermissionState?
    private var lastSurface: CodexActionableSurface?

    private struct SnapshotBuildContext {
        var elementsByNodeID: [String: AXUIElement] = [:]
    }

    public init(
        bundleIdentifier: String = "com.openai.codex",
        pollInterval: TimeInterval = 0.75,
        snapshotDepth: Int = 8,
        webAreaSnapshotDepth: Int = 26,
        navigationSnapshotDepth: Int = 4,
        permissionChecker: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        runningApplicationProvider: @escaping @Sendable (String) -> NSRunningApplication? = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.pollInterval = pollInterval
        self.snapshotDepth = max(5, snapshotDepth)
        self.webAreaSnapshotDepth = max(self.snapshotDepth, webAreaSnapshotDepth)
        self.navigationSnapshotDepth = max(1, navigationSnapshotDepth)
        self.permissionChecker = permissionChecker
        self.runningApplicationProvider = runningApplicationProvider
        self.inspector = CodexDesktopAXInspector()
        self.actionResolver = CodexDesktopAXActionResolver()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.isRunning == false else {
                return
            }

            self.isRunning = true
            self.scheduleTimer()
            self.refresh()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.actionResolver.reset()
            self.updateSurface(nil)
        }
    }

    @discardableResult
    public func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool {
        actionResolver.perform(action: action, on: surfaceID)
    }

    @discardableResult
    public func selectOption(_ optionID: String, on surfaceID: String) -> Bool {
        actionResolver.selectOption(optionID, on: surfaceID)
    }

    @discardableResult
    public func updateText(_ text: String, on surfaceID: String) -> Bool {
        actionResolver.updateText(text, on: surfaceID)
    }

    private func scheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
    }

    private func refresh() {
        let permissionState = permissionChecker() ? CodexDesktopAXPermissionState.granted : .notGranted
        emitPermissionState(permissionState)

        guard permissionState.status == .granted else {
            logger.debug("Accessibility permission not granted for Codex AX monitoring.")
            actionResolver.reset()
            updateSurface(nil)
            return
        }

        guard let app = runningApplicationProvider(bundleIdentifier) else {
            logger.debug("Codex application not running; AX surface cleared.")
            actionResolver.reset()
            updateSurface(nil)
            return
        }

        actionResolver.reset()
        guard let snapshot = buildSnapshot(for: app) else {
            logger.debug("Failed to build Codex AX snapshot.")
            updateSurface(nil)
            return
        }

        for (nodeID, element) in snapshot.context.elementsByNodeID {
            actionResolver.registerElement(element, nodeID: nodeID)
        }

        guard let inspection = inspector.inspect(snapshot: snapshot.snapshot) else {
            let metrics = snapshotMetrics(snapshot.snapshot)
            logger.debug(
                "No Codex AX surface detected. windows=\(snapshot.snapshot.windows.count) webAreas=\(metrics.webAreas) buttons=\(metrics.buttons) texts=\(metrics.textContent)"
            )
            updateSurface(nil)
            return
        }

        actionResolver.registerSurface(
            surfaceID: inspection.surface.id,
            primaryNodeID: inspection.primaryActionNodeID,
            cancelNodeID: inspection.cancelActionNodeID,
            optionNodeIDs: inspection.surface.options.map(\.id),
            textInputNodeID: inspection.textInputNodeID
        )
        logger.debug(
            "Detected Codex AX surface id=\(inspection.surface.id, privacy: .public) primary=\(inspection.surface.primaryButtonTitle, privacy: .public) cancel=\(inspection.surface.cancelButtonTitle, privacy: .public)"
        )
        updateSurface(inspection.surface)
    }

    private func emitPermissionState(_ state: CodexDesktopAXPermissionState) {
        guard lastPermissionState != state else {
            return
        }

        lastPermissionState = state
        onPermissionStateChanged?(state)
    }

    private func updateSurface(_ surface: CodexActionableSurface?) {
        guard lastSurface != surface else {
            return
        }

        lastSurface = surface
        onSurfaceChanged?(surface)
    }

    private func buildSnapshot(
        for app: NSRunningApplication
    ) -> (snapshot: CodexDesktopAXSnapshot, context: SnapshotBuildContext)? {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = copyElementAttribute(applicationElement, attribute: kAXFocusedWindowAttribute)
        let allWindows = copyElementArrayAttribute(applicationElement, attribute: kAXWindowsAttribute)

        var orderedWindows: [AXUIElement] = []
        if let focusedWindow {
            orderedWindows.append(focusedWindow)
        }
        for window in allWindows where orderedWindows.contains(where: { CFEqual($0, window) }) == false {
            orderedWindows.append(window)
        }

        guard orderedWindows.isEmpty == false else {
            return nil
        }

        var context = SnapshotBuildContext()
        var snapshots: [CodexDesktopAXWindowSnapshot] = []
        for (index, window) in orderedWindows.enumerated() {
            guard let root = snapshotNode(
                for: window,
                nodeID: "window-\(index)",
                remainingDepth: snapshotDepth,
                context: &context
            ) else {
                continue
            }

            snapshots.append(
                CodexDesktopAXWindowSnapshot(
                    id: root.id,
                    isFocused: focusedWindow.map { CFEqual($0, window) } ?? false,
                    root: root
                )
            )
        }

        guard snapshots.isEmpty == false else {
            return nil
        }

        return (
            snapshot: CodexDesktopAXSnapshot(pid: app.processIdentifier, windows: snapshots),
            context: context
        )
    }

    private func snapshotNode(
        for element: AXUIElement,
        nodeID: String,
        remainingDepth: Int,
        context: inout SnapshotBuildContext
    ) -> CodexDesktopAXNode? {
        let role = copyStringAttribute(element, attribute: kAXRoleAttribute) ?? ""
        let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute)
        let title = copyStringAttribute(element, attribute: kAXTitleAttribute)
        let description = copyStringAttribute(element, attribute: kAXDescriptionAttribute)
        let value = copyStringAttribute(element, attribute: kAXValueAttribute)
        let selected: Bool?
        if role == "AXRadioButton" {
            selected = copyBoolAttribute(element, attribute: kAXValueAttribute)
                ?? copyBoolAttribute(element, attribute: "AXSelected")
        } else {
            selected = copyBoolAttribute(element, attribute: "AXSelected")
        }
        let isValueSettable = isAttributeSettable(element, attribute: kAXValueAttribute)
        let isEnabled = copyBoolAttribute(element, attribute: kAXEnabledAttribute) ?? true

        if axInteractiveRoles.contains(role) {
            context.elementsByNodeID[nodeID] = element
        }

        let children: [CodexDesktopAXNode]
        if remainingDepth > 0 {
            let childDepth = childSnapshotDepth(
                parentRole: role,
                parentSubrole: subrole,
                remainingDepth: remainingDepth
            )
            children = combinedChildElements(for: element).enumerated().compactMap { index, child in
                snapshotNode(
                    for: child,
                    nodeID: "\(nodeID).\(index)",
                    remainingDepth: childDepth,
                    context: &context
                )
            }
        } else {
            children = []
        }

        return CodexDesktopAXNode(
            id: nodeID,
            role: role,
            subrole: subrole,
            title: title,
            description: description,
            value: value,
            selected: selected,
            isValueSettable: isValueSettable,
            isEnabled: isEnabled,
            children: children
        )
    }

    private func combinedChildElements(for element: AXUIElement) -> [AXUIElement] {
        copyElementArrayAttribute(element, attribute: kAXChildrenAttribute)
    }

    private func childSnapshotDepth(
        parentRole: String,
        parentSubrole: String?,
        remainingDepth: Int
    ) -> Int {
        let defaultChildDepth = max(remainingDepth - 1, 0)

        if parentSubrole == "AXLandmarkNavigation" {
            return min(defaultChildDepth, max(navigationSnapshotDepth - 1, 0))
        }

        if parentRole == "AXWebArea" {
            return max(defaultChildDepth, max(webAreaSnapshotDepth - 1, 0))
        }

        return defaultChildDepth
    }

    private func snapshotMetrics(_ snapshot: CodexDesktopAXSnapshot) -> (buttons: Int, textContent: Int, webAreas: Int) {
        snapshot.windows.reduce(into: (buttons: 0, textContent: 0, webAreas: 0)) { partialResult, window in
            accumulateMetrics(for: window.root, into: &partialResult)
        }
    }

    private func accumulateMetrics(
        for node: CodexDesktopAXNode,
        into metrics: inout (buttons: Int, textContent: Int, webAreas: Int)
    ) {
        switch node.role {
        case "AXButton":
            metrics.buttons += 1
        case "AXStaticText", "AXHeading":
            metrics.textContent += 1
        case "AXWebArea":
            metrics.webAreas += 1
        default:
            break
        }

        for child in node.children {
            accumulateMetrics(for: child, into: &metrics)
        }
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }

    private func copyBoolAttribute(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber
        else {
            return nil
        }
        return number.boolValue
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }

        let element: AXUIElement = value as! AXUIElement
        return element
    }

    private func copyElementArrayAttribute(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [Any]
        else {
            return []
        }

        return array.map { $0 as! AXUIElement }
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: String) -> Bool? {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        guard result == .success else {
            return nil
        }
        return settable.boolValue
    }
}

private let axInteractiveRoles: Set<String> = [
    kAXButtonRole as String,
    "AXRadioButton",
    "AXTextArea",
    "AXTextField",
]

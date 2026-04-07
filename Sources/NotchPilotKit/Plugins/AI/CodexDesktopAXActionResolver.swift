import ApplicationServices
import Foundation

public final class CodexDesktopAXActionResolver {
    private struct SurfaceBinding {
        let primaryNodeID: String
        let cancelNodeID: String
        let optionNodeIDs: Set<String>
        let textInputNodeID: String?
    }

    private let lock = NSLock()
    private var elementsByNodeID: [String: AXUIElement] = [:]
    private var surfaceBindings: [String: SurfaceBinding] = [:]

    public init() {}

    public func reset() {
        lock.lock()
        elementsByNodeID.removeAll()
        surfaceBindings.removeAll()
        lock.unlock()
    }

    public func registerElement(_ element: AXUIElement, nodeID: String) {
        lock.lock()
        elementsByNodeID[nodeID] = element
        lock.unlock()
    }

    public func registerSurface(
        surfaceID: String,
        primaryNodeID: String,
        cancelNodeID: String,
        optionNodeIDs: [String] = [],
        textInputNodeID: String? = nil
    ) {
        lock.lock()
        surfaceBindings[surfaceID] = SurfaceBinding(
            primaryNodeID: primaryNodeID,
            cancelNodeID: cancelNodeID,
            optionNodeIDs: Set(optionNodeIDs),
            textInputNodeID: textInputNodeID
        )
        lock.unlock()
    }

    @discardableResult
    public func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool {
        let binding: SurfaceBinding?
        let elements: [String: AXUIElement]

        lock.lock()
        binding = surfaceBindings[surfaceID]
        elements = elementsByNodeID
        lock.unlock()

        guard let binding else {
            return false
        }

        switch action {
        case .primary:
            guard let element = elements[binding.primaryNodeID] else {
                return false
            }
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        case .cancel:
            guard let element = elements[binding.cancelNodeID] else {
                return false
            }
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
    }

    @discardableResult
    public func selectOption(_ optionID: String, on surfaceID: String) -> Bool {
        let binding: SurfaceBinding?
        let elements: [String: AXUIElement]

        lock.lock()
        binding = surfaceBindings[surfaceID]
        elements = elementsByNodeID
        lock.unlock()

        guard let binding,
              binding.optionNodeIDs.contains(optionID),
              let element = elements[optionID]
        else {
            return false
        }

        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    public func updateText(_ text: String, on surfaceID: String) -> Bool {
        let binding: SurfaceBinding?
        let elements: [String: AXUIElement]

        lock.lock()
        binding = surfaceBindings[surfaceID]
        elements = elementsByNodeID
        lock.unlock()

        guard let binding,
              let textInputNodeID = binding.textInputNodeID,
              let element = elements[textInputNodeID]
        else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }
}

import Combine
import CoreGraphics
import Foundation

@MainActor
public final class ScreenSessionModel: ObservableObject {
    private enum OpenReason {
        case hover
        case manual
        case programmatic
    }

    private static let fallbackExpandedSize = CGSize(width: 520, height: 320)
    private static let hoverOpenDelay: Duration = .milliseconds(120)
    private static let hoverCloseDelay: Duration = .milliseconds(100)
    private static let horizontalHoverPadding: CGFloat = 30
    private static let bottomHoverPadding: CGFloat = 10
    private static let shadowPadding: CGFloat = 20

    @Published public private(set) var descriptor: ScreenDescriptor
    @Published public private(set) var notchState: NotchState = .idleClosed
    @Published public private(set) var hoverState = false
    @Published public private(set) var currentSneakPeek: SneakPeekRequest?
    @Published public var activePluginID: String?
    @Published public private(set) var lastSelectedPluginID: String?

    public var id: String { descriptor.id }
    public var layoutDidChange: (() -> Void)?

    private let queue = SneakPeekQueue()
    private var autoDismissTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?
    private var openReason: OpenReason?

    public init(descriptor: ScreenDescriptor) {
        self.descriptor = descriptor
    }

    public var currentSize: CGSize {
        switch notchState {
        case .open:
            return geometry.expandedSize
        case .previewClosed, .idleClosed:
            return geometry.compactSize
        }
    }

    public var geometry: NotchGeometry {
        let compactSize = descriptor.closedNotchSize ?? NotchSizing.fallbackCompactSize
        let expandedSize = CGSize(
            width: max(Self.fallbackExpandedSize.width, compactSize.width + 220),
            height: Self.fallbackExpandedSize.height
        )

        return NotchGeometry(compactSize: compactSize, expandedSize: expandedSize)
    }

    public var showsSneakPeekOverlay: Bool {
        notchState == .previewClosed && currentSneakPeek != nil
    }

    public var windowSize: CGSize {
        CGSize(
            width: geometry.expandedSize.width,
            height: geometry.expandedSize.height + Self.shadowPadding
        )
    }

    public var interactionSize: CGSize {
        if notchState == .open {
            return currentSize
        }

        return CGSize(
            width: currentSize.width + (Self.horizontalHoverPadding * 2),
            height: currentSize.height + Self.bottomHoverPadding
        )
    }

    public var windowFrame: CGRect {
        let size = windowSize
        let origin = CGPoint(
            x: descriptor.frame.midX - (size.width / 2),
            y: descriptor.frame.maxY - size.height
        )
        return CGRect(origin: origin, size: size)
    }

    public func interactionFrame(for interactionSize: CGSize) -> CGRect {
        let currentWindowFrame = windowFrame
        let origin = CGPoint(
            x: currentWindowFrame.midX - (interactionSize.width / 2),
            y: currentWindowFrame.maxY - interactionSize.height
        )
        return CGRect(origin: origin, size: interactionSize)
    }

    public func updateScreen(_ descriptor: ScreenDescriptor) {
        self.descriptor = descriptor
        layoutDidChange?()
    }

    public func setHover(_ hovering: Bool, fallbackPluginID: String?) {
        hoverState = hovering

        if hovering {
            hoverCloseTask?.cancel()
            scheduleHoverOpen(fallbackPluginID: fallbackPluginID)

            return
        }

        hoverOpenTask?.cancel()

        guard openReason == .hover else {
            return
        }

        scheduleHoverClose()
    }

    public func toggleOpen(defaultPluginID: String?) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()

        if notchState == .open, openReason == .manual {
            close()
        } else {
            open(pluginID: currentSneakPeek?.pluginID ?? lastSelectedPluginID ?? activePluginID ?? defaultPluginID, reason: .manual)
        }
    }

    public func open(pluginID: String?) {
        open(pluginID: pluginID, reason: .programmatic)
    }

    func openForHover(pluginID: String?) {
        open(pluginID: pluginID, reason: .hover)
    }

    private func open(pluginID: String?, reason: OpenReason) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        if let pluginID {
            activePluginID = pluginID
            lastSelectedPluginID = pluginID
        }
        openReason = reason
        notchState = .open
        layoutDidChange?()
    }

    public func close() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        openReason = nil
        updatePresentationState()
        layoutDidChange?()
    }

    public func enqueue(_ request: SneakPeekRequest) {
        queue.enqueue(request)
        refreshCurrentSneakPeek()
    }

    public func dismissSneakPeek(requestID: UUID?) {
        if let requestID {
            _ = queue.expire(requestID)
        } else {
            _ = queue.dismissCurrent()
        }
        refreshCurrentSneakPeek()
    }

    private func refreshCurrentSneakPeek() {
        autoDismissTask?.cancel()
        currentSneakPeek = queue.current

        if let request = currentSneakPeek, let delay = request.autoDismissAfter {
            autoDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard Task.isCancelled == false else {
                    return
                }
                self?.dismissSneakPeek(requestID: request.id)
            }
        } else {
            autoDismissTask = nil
        }

        if notchState != .open {
            updatePresentationState()
            layoutDidChange?()
        }
    }

    private func scheduleHoverClose() {
        hoverCloseTask?.cancel()
        hoverCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hoverCloseDelay)
            guard
                let self,
                !Task.isCancelled,
                self.hoverState == false,
                self.openReason == .hover,
                self.notchState == .open
            else {
                return
            }
            self.close()
        }
    }

    private func scheduleHoverOpen(fallbackPluginID: String?) {
        guard notchState != .open else {
            return
        }

        hoverOpenTask?.cancel()
        hoverOpenTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hoverOpenDelay)
            guard
                let self,
                !Task.isCancelled,
                self.hoverState,
                self.notchState != .open
            else {
                return
            }

            self.openForHover(
                pluginID: self.currentSneakPeek?.pluginID
                    ?? self.lastSelectedPluginID
                    ?? self.activePluginID
                    ?? fallbackPluginID
            )
        }
    }

    private func updatePresentationState() {
        notchState = currentSneakPeek == nil ? .idleClosed : .previewClosed
    }
}

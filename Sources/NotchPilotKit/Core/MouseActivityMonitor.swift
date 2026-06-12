import AppKit
import Foundation

enum MouseActivityScope {
    case local
    case global
}

struct MouseActivityEvent {
    let scope: MouseActivityScope
    let event: NSEvent
}

enum MouseActivityHandlingResult {
    case passThrough
    case consumeEvent
}

@MainActor
protocol MouseActivityMonitoring: AnyObject {
    @discardableResult
    func addSubscriber(
        _ handler: @escaping @MainActor (MouseActivityEvent) -> MouseActivityHandlingResult
    ) -> UUID
    func removeSubscriber(_ token: UUID)
}

protocol MouseEventMonitoring {
    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any?
    func removeMonitor(_ monitor: Any)
}

struct AppKitMouseEventMonitor: MouseEventMonitoring {
    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

@MainActor
final class MouseActivityMonitor: MouseActivityMonitoring {
    static let shared = MouseActivityMonitor()

    private static let eventMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .swipe,
    ]

    private let eventMonitor: any MouseEventMonitoring
    private var subscribers: [UUID: @MainActor (MouseActivityEvent) -> MouseActivityHandlingResult] = [:]
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(eventMonitor: any MouseEventMonitoring = AppKitMouseEventMonitor()) {
        self.eventMonitor = eventMonitor
    }

    @discardableResult
    func addSubscriber(
        _ handler: @escaping @MainActor (MouseActivityEvent) -> MouseActivityHandlingResult
    ) -> UUID {
        let token = UUID()
        subscribers[token] = handler
        installMonitorsIfNeeded()
        return token
    }

    func removeSubscriber(_ token: UUID) {
        subscribers[token] = nil
        removeMonitorsIfIdle()
    }

    private func installMonitorsIfNeeded() {
        guard subscribers.isEmpty == false,
              localMouseMonitor == nil,
              globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = eventMonitor.addLocalMonitor(matching: Self.eventMask) { [weak self] event in
            var shouldConsumeEvent = false
            MainActor.assumeIsolated {
                shouldConsumeEvent = self?.notifySubscribers(scope: .local, event: event) == true
            }
            return shouldConsumeEvent ? nil : event
        }

        globalMouseMonitor = eventMonitor.addGlobalMonitor(matching: Self.eventMask) { [weak self] event in
            MainActor.assumeIsolated {
                _ = self?.notifySubscribers(scope: .global, event: event)
            }
        }
    }

    private func removeMonitorsIfIdle() {
        guard subscribers.isEmpty else {
            return
        }

        if let localMouseMonitor {
            eventMonitor.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            eventMonitor.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func notifySubscribers(scope: MouseActivityScope, event: NSEvent) -> Bool {
        let activity = MouseActivityEvent(scope: scope, event: event)
        var shouldConsumeEvent = false

        for handler in subscribers.values {
            if handler(activity) == .consumeEvent {
                shouldConsumeEvent = true
            }
        }

        return shouldConsumeEvent
    }
}

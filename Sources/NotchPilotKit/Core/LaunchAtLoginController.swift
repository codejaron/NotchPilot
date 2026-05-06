import Foundation
import ServiceManagement

@MainActor
public protocol LaunchAtLoginControlling: AnyObject {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public final class SMAppServiceLaunchAtLoginController: LaunchAtLoginControlling {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public func isEnabled() -> Bool {
        service.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }
}

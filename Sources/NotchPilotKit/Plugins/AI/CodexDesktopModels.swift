import Foundation

public enum CodexThreadPhase: String, Equatable, Sendable {
    case plan
    case working
    case completed
    case connected
    case interrupted
    case error
    case unknown
}

public struct CodexThreadContext: Equatable, Sendable, Identifiable {
    public var id: String { threadID }

    public let threadID: String
    public let title: String?
    public let activityLabel: String
    public let phase: CodexThreadPhase
    public let inputTokenCount: Int?
    public let outputTokenCount: Int?
    public let updatedAt: Date

    public init(
        threadID: String,
        title: String?,
        activityLabel: String,
        phase: CodexThreadPhase,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.threadID = threadID
        self.title = title
        self.activityLabel = activityLabel
        self.phase = phase
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.updatedAt = updatedAt
    }
}

public enum CodexSurfaceAction: String, Equatable, Sendable {
    case primary
    case cancel
}

public struct CodexSurfaceOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let index: Int
    public let title: String
    public let isSelected: Bool

    public init(id: String, index: Int, title: String, isSelected: Bool) {
        self.id = id
        self.index = index
        self.title = title
        self.isSelected = isSelected
    }
}

public struct CodexSurfaceTextInput: Equatable, Sendable {
    public let title: String?
    public let text: String
    public let isEditable: Bool

    public init(title: String? = nil, text: String, isEditable: Bool) {
        self.title = title
        self.text = text
        self.isEditable = isEditable
    }
}

public struct CodexActionableSurface: Equatable, Sendable, Identifiable {
    public let id: String
    public let summary: String
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String
    public let options: [CodexSurfaceOption]
    public let textInput: CodexSurfaceTextInput?
    public let threadID: String?
    public let threadTitle: String?

    public init(
        id: String,
        summary: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String,
        options: [CodexSurfaceOption] = [],
        textInput: CodexSurfaceTextInput? = nil,
        threadID: String? = nil,
        threadTitle: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.primaryButtonTitle = primaryButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.options = options
        self.textInput = textInput
        self.threadID = threadID
        self.threadTitle = threadTitle
    }

    public func merged(with context: CodexThreadContext?) -> CodexActionableSurface {
        guard let context else {
            return self
        }

        return CodexActionableSurface(
            id: id,
            summary: summary,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            options: options,
            textInput: textInput,
            threadID: threadID ?? context.threadID,
            threadTitle: threadTitle ?? context.title
        )
    }

    public func selectingOption(_ optionID: String) -> CodexActionableSurface {
        guard options.isEmpty == false else {
            return self
        }

        return CodexActionableSurface(
            id: id,
            summary: summary,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            options: options.map { option in
                CodexSurfaceOption(
                    id: option.id,
                    index: option.index,
                    title: option.title,
                    isSelected: option.id == optionID
                )
            },
            textInput: textInput,
            threadID: threadID,
            threadTitle: threadTitle
        )
    }

    public func updatingText(_ text: String) -> CodexActionableSurface {
        guard let textInput else {
            return self
        }

        return CodexActionableSurface(
            id: id,
            summary: summary,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            options: options,
            textInput: CodexSurfaceTextInput(
                title: textInput.title,
                text: text,
                isEditable: textInput.isEditable
            ),
            threadID: threadID,
            threadTitle: threadTitle
        )
    }
}

public enum CodexDesktopAXPermissionStatus: String, Equatable, Sendable {
    case granted
    case notGranted
}

public struct CodexDesktopAXPermissionState: Equatable, Sendable {
    public let status: CodexDesktopAXPermissionStatus
    public let message: String?

    public init(status: CodexDesktopAXPermissionStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }

    public static let granted = CodexDesktopAXPermissionState(status: .granted)
    public static let notGranted = CodexDesktopAXPermissionState(
        status: .notGranted,
        message: "Accessibility permission is required for Codex actions."
    )
}

public protocol CodexDesktopContextMonitoring: AnyObject {
    var onThreadContextChanged: (@Sendable (CodexThreadContext) -> Void)? { get set }
    var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)? { get set }

    func start()
    func stop()
}

public protocol CodexDesktopAXMonitoring: AnyObject {
    var onPermissionStateChanged: (@Sendable (CodexDesktopAXPermissionState) -> Void)? { get set }
    var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)? { get set }

    func start()
    func stop()

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool
}

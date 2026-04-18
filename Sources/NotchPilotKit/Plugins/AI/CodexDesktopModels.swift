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
    public let launchContext: AISessionLaunchContext?

    public init(
        threadID: String,
        title: String?,
        activityLabel: String,
        phase: CodexThreadPhase,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        updatedAt: Date = Date(),
        launchContext: AISessionLaunchContext? = nil
    ) {
        self.threadID = threadID
        self.title = title
        self.activityLabel = activityLabel
        self.phase = phase
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.updatedAt = updatedAt
        self.launchContext = launchContext?.isEmpty == true ? nil : launchContext
    }
}

public struct CodexThreadUpdate: Equatable, Sendable {
    public let context: CodexThreadContext
    public let marksActivity: Bool

    public init(context: CodexThreadContext, marksActivity: Bool) {
        self.context = context
        self.marksActivity = marksActivity
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
    public let attachedOptionID: String?

    public init(
        title: String? = nil,
        text: String,
        isEditable: Bool,
        attachedOptionID: String? = nil
    ) {
        self.title = title
        self.text = text
        self.isEditable = isEditable
        self.attachedOptionID = attachedOptionID
    }
}

public struct CodexActionableSurface: Equatable, Sendable, Identifiable {
    public let id: String
    public let summary: String
    public let commandPreview: String?
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String
    public let options: [CodexSurfaceOption]
    public let textInput: CodexSurfaceTextInput?
    public let threadID: String?
    public let threadTitle: String?

    public init(
        id: String,
        summary: String,
        commandPreview: String? = nil,
        primaryButtonTitle: String,
        cancelButtonTitle: String,
        options: [CodexSurfaceOption] = [],
        textInput: CodexSurfaceTextInput? = nil,
        threadID: String? = nil,
        threadTitle: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.commandPreview = commandPreview
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

        let resolvedThreadTitle = Self.preferredThreadTitle(
            contextTitle: context.title
        )

        return CodexActionableSurface(
            id: id,
            summary: summary,
            commandPreview: commandPreview,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            options: options,
            textInput: textInput,
            threadID: threadID ?? context.threadID,
            threadTitle: resolvedThreadTitle
        )
    }

    public func selectingOption(_ optionID: String) -> CodexActionableSurface {
        guard options.isEmpty == false else {
            return self
        }

        return CodexActionableSurface(
            id: id,
            summary: summary,
            commandPreview: commandPreview,
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
            commandPreview: commandPreview,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            options: options,
            textInput: CodexSurfaceTextInput(
                title: textInput.title,
                text: text,
                isEditable: textInput.isEditable,
                attachedOptionID: textInput.attachedOptionID
            ),
            threadID: threadID,
            threadTitle: threadTitle
        )
    }

    private static func preferredThreadTitle(
        contextTitle: String?
    ) -> String? {
        normalizedThreadTitle(contextTitle)
    }

    private static func normalizedThreadTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false
        else {
            return nil
        }

        return title
    }
}

public protocol CodexDesktopContextMonitoring: AnyObject {
    var onThreadContextChanged: (@Sendable (CodexThreadUpdate) -> Void)? { get set }
    var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)? { get set }

    func start()
    func stop()

    @discardableResult
    func focusThread(id: String) -> Bool
}

public protocol CodexDesktopActionableSurfaceMonitoring: AnyObject {
    var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)? { get set }

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool
}

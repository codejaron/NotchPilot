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
    public let contextInputTokenCount: Int?
    public let contextWindowTokenCount: Int?
    public let updatedAt: Date
    public let launchContext: AISessionLaunchContext?

    public init(
        threadID: String,
        title: String?,
        activityLabel: String,
        phase: CodexThreadPhase,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        contextInputTokenCount: Int? = nil,
        contextWindowTokenCount: Int? = nil,
        updatedAt: Date = Date(),
        launchContext: AISessionLaunchContext? = nil
    ) {
        self.threadID = threadID
        self.title = title
        self.activityLabel = activityLabel
        self.phase = phase
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.contextInputTokenCount = contextInputTokenCount
        self.contextWindowTokenCount = contextWindowTokenCount
        self.updatedAt = updatedAt
        self.launchContext = launchContext?.isEmpty == true ? nil : launchContext
    }

    public var contextUsagePercent: Double? {
        guard let contextWindowTokenCount, contextWindowTokenCount > 0 else {
            return nil
        }

        let contextTokens = contextInputTokenCount ?? ((inputTokenCount ?? 0) + (outputTokenCount ?? 0))
        guard contextTokens > 0 else {
            return 0
        }

        return min(100, max(0, Double(contextTokens) / Double(contextWindowTokenCount) * 100))
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

public struct CodexSurfaceQuickActions: Equatable, Sendable {
    public let approveOptionID: String?
    public let rejectOptionID: String?
    public let rejectUsesCancel: Bool

    public init(
        approveOptionID: String? = nil,
        rejectOptionID: String? = nil,
        rejectUsesCancel: Bool = false
    ) {
        self.approveOptionID = approveOptionID
        self.rejectOptionID = rejectOptionID
        self.rejectUsesCancel = rejectUsesCancel
    }

    public static let none = CodexSurfaceQuickActions()
}

public struct CodexFileChange: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case add
        case update
        case delete
        case move
    }

    public let id: String
    public let path: String
    public let displayPath: String
    public let kind: Kind
    public let addedLines: Int
    public let removedLines: Int

    public init(
        id: String,
        path: String,
        displayPath: String,
        kind: Kind,
        addedLines: Int,
        removedLines: Int
    ) {
        self.id = id
        self.path = path
        self.displayPath = displayPath
        self.kind = kind
        self.addedLines = addedLines
        self.removedLines = removedLines
    }
}

public struct CodexActionableSurface: Equatable, Sendable, Identifiable {
    public let id: String
    public let summary: String
    public let commandPreview: String?
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String
    public let showsActionButtons: Bool
    public let options: [CodexSurfaceOption]
    public let textInput: CodexSurfaceTextInput?
    public let fileChanges: [CodexFileChange]
    public let threadID: String?
    public let threadTitle: String?
    public let quickActions: CodexSurfaceQuickActions

    public init(
        id: String,
        summary: String,
        commandPreview: String? = nil,
        primaryButtonTitle: String,
        cancelButtonTitle: String,
        showsActionButtons: Bool = true,
        options: [CodexSurfaceOption] = [],
        textInput: CodexSurfaceTextInput? = nil,
        fileChanges: [CodexFileChange] = [],
        threadID: String? = nil,
        threadTitle: String? = nil,
        quickActions: CodexSurfaceQuickActions = .none
    ) {
        self.id = id
        self.summary = summary
        self.commandPreview = commandPreview
        self.primaryButtonTitle = primaryButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.showsActionButtons = showsActionButtons
        self.options = options
        self.textInput = textInput
        self.fileChanges = fileChanges
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.quickActions = quickActions
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
            showsActionButtons: showsActionButtons,
            options: options,
            textInput: textInput,
            fileChanges: fileChanges,
            threadID: threadID ?? context.threadID,
            threadTitle: resolvedThreadTitle,
            quickActions: quickActions
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
            showsActionButtons: showsActionButtons,
            options: options.map { option in
                CodexSurfaceOption(
                    id: option.id,
                    index: option.index,
                    title: option.title,
                    isSelected: option.id == optionID
                )
            },
            textInput: textInput,
            fileChanges: fileChanges,
            threadID: threadID,
            threadTitle: threadTitle,
            quickActions: quickActions
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
            showsActionButtons: showsActionButtons,
            options: options,
            textInput: CodexSurfaceTextInput(
                title: textInput.title,
                text: text,
                isEditable: textInput.isEditable,
                attachedOptionID: textInput.attachedOptionID
            ),
            fileChanges: fileChanges,
            threadID: threadID,
            threadTitle: threadTitle,
            quickActions: quickActions
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

public protocol CodexDesktopContextMonitoring: AnyObject, Sendable {
    var onThreadContextChanged: (@Sendable (CodexThreadUpdate) -> Void)? { get set }
    var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)? { get set }

    func start()
    func stop()

    @discardableResult
    func focusThread(id: String) -> Bool
}

public protocol CodexDesktopActionableSurfaceMonitoring: AnyObject, Sendable {
    var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)? { get set }

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool
}

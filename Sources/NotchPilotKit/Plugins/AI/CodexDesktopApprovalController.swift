import Foundation

enum CodexDesktopApprovalSubmission: Equatable, Sendable {
    case response
    case request(
        method: String,
        params: [String: JSONValue],
        targetClientID: String?,
        version: Int
    )
}

struct CodexDesktopApprovalResponse: Equatable, Sendable {
    let requestID: String
    let method: String
    let result: JSONValue
    let submission: CodexDesktopApprovalSubmission
    let followUpSubmission: CodexDesktopApprovalSubmission?
    let fallbackFollowUpSubmission: CodexDesktopApprovalSubmission?
    let followUpConversationID: String?

    init(
        requestID: String,
        method: String,
        result: JSONValue,
        submission: CodexDesktopApprovalSubmission,
        followUpSubmission: CodexDesktopApprovalSubmission? = nil,
        fallbackFollowUpSubmission: CodexDesktopApprovalSubmission? = nil,
        followUpConversationID: String? = nil
    ) {
        self.requestID = requestID
        self.method = method
        self.result = result
        self.submission = submission
        self.followUpSubmission = followUpSubmission
        self.fallbackFollowUpSubmission = fallbackFollowUpSubmission
        self.followUpConversationID = followUpConversationID
    }
}

final class CodexDesktopApprovalController {
    private enum Delivery: Equatable {
        case response
        case threadFollower(ownerClientID: String, conversationID: String, version: Int)
    }

    private struct FollowUpRequest {
        let threadID: String
        let turnID: JSONValue?
        let cwd: String?
    }

    private struct FeedbackFollowUpPlan {
        let preferredSubmission: CodexDesktopApprovalSubmission
        let fallbackSubmission: CodexDesktopApprovalSubmission?
        let conversationID: String
    }

    private enum SelectionMode {
        case optionResults([String: JSONValue])
        case optionResultsWithOther(
            [String: JSONValue],
            negativeResult: JSONValue,
            followUp: FollowUpRequest?
        )
        case userInput(
            questionID: String,
            optionAnswersByOptionID: [String: String],
            isOther: Bool
        )
    }

    private struct PendingApproval {
        let requestID: String
        let rawRequestID: JSONValue
        let method: String
        let selectionMode: SelectionMode
        let cancelResult: JSONValue
        let delivery: Delivery
        let followUpDelivery: Delivery
        var surface: CodexActionableSurface
    }

    private enum SupportedMethod: String {
        case commandExecution = "item/commandExecution/requestApproval"
        case fileChange = "item/fileChange/requestApproval"
        case toolRequestUserInput = "item/tool/requestUserInput"
        case legacyExecCommand = "execCommandApproval"
        case legacyApplyPatch = "applyPatchApproval"
    }

    private var pendingApproval: PendingApproval?
    private let followUpCreatedAtMillisecondsProvider: @Sendable () -> Int

    init(
        followUpCreatedAtMillisecondsProvider: @escaping @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970 * 1000)
        }
    ) {
        self.followUpCreatedAtMillisecondsProvider = followUpCreatedAtMillisecondsProvider
    }

    var currentSurface: CodexActionableSurface? {
        pendingApproval?.surface
    }

    static func canHandle(_ request: CodexDesktopIPCRequestFrame?) -> Bool {
        guard let method = request?.method else {
            return false
        }

        return SupportedMethod(rawValue: method) != nil
    }

    func handle(request: CodexDesktopIPCRequestFrame) -> CodexActionableSurface? {
        handle(request: request, delivery: .response)
    }

    func handleLiveRequest(_ request: CodexDesktopIPCRequestFrame) -> CodexActionableSurface? {
        guard let delivery = liveDelivery(for: request) else {
            return handle(request: request)
        }

        return handle(request: request, delivery: delivery)
    }

    private func handle(
        request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> CodexActionableSurface? {
        guard let method = SupportedMethod(rawValue: request.method) else {
            return nil
        }

        let pendingApproval: PendingApproval
        switch method {
        case .commandExecution:
            pendingApproval = makeCommandApproval(from: request, delivery: delivery)
        case .fileChange:
            pendingApproval = makeFileChangeApproval(from: request, delivery: delivery)
        case .toolRequestUserInput:
            pendingApproval = makeUserInputRequest(from: request, delivery: delivery)
        case .legacyExecCommand:
            pendingApproval = makeLegacyCommandApproval(from: request, delivery: delivery)
        case .legacyApplyPatch:
            pendingApproval = makeLegacyPatchApproval(from: request, delivery: delivery)
        }

        self.pendingApproval = pendingApproval
        return pendingApproval.surface
    }

    func selectOption(_ optionID: String, on surfaceID: String) -> CodexActionableSurface? {
        guard var pendingApproval,
              pendingApproval.surface.id == surfaceID,
              pendingApproval.surface.options.contains(where: { $0.id == optionID })
        else {
            return nil
        }

        pendingApproval.surface = pendingApproval.surface.selectingOption(optionID)
        self.pendingApproval = pendingApproval
        return pendingApproval.surface
    }

    func updateText(_ text: String, on surfaceID: String) -> CodexActionableSurface? {
        guard var pendingApproval,
              pendingApproval.surface.id == surfaceID,
              pendingApproval.surface.textInput != nil
        else {
            return nil
        }

        let updatedSurface = pendingApproval.surface.updatingText(text)
        pendingApproval.surface = shouldClearSelectionOnTextUpdate(for: pendingApproval.selectionMode)
            ? surfaceByClearingSelection(updatedSurface)
            : updatedSurface
        self.pendingApproval = pendingApproval
        return pendingApproval.surface
    }

    func perform(action: CodexSurfaceAction, on surfaceID: String) -> CodexDesktopApprovalResponse? {
        guard let pendingApproval,
              pendingApproval.surface.id == surfaceID
        else {
            return nil
        }

        let response: CodexDesktopApprovalResponse
        switch action {
        case .cancel:
            response = CodexDesktopApprovalResponse(
                requestID: pendingApproval.requestID,
                method: pendingApproval.method,
                result: pendingApproval.cancelResult,
                submission: submission(for: pendingApproval, result: pendingApproval.cancelResult)
            )
        case .primary:
            let selectedOptionID = pendingApproval.surface.options.first(where: \.isSelected)?.id
            let trimmedText = normalizedInputText(pendingApproval.surface.textInput?.text)

            switch pendingApproval.selectionMode {
            case let .optionResults(responsesByOptionID):
                let effectiveOptionID = selectedOptionID ?? pendingApproval.surface.options.first?.id
                guard let effectiveOptionID,
                      let result = responsesByOptionID[effectiveOptionID]
                else {
                    return nil
                }

                response = CodexDesktopApprovalResponse(
                    requestID: pendingApproval.requestID,
                    method: pendingApproval.method,
                    result: result,
                    submission: submission(for: pendingApproval, result: result)
                )
            case let .optionResultsWithOther(responsesByOptionID, negativeResult, followUp):
                if let selectedOptionID,
                   let result = responsesByOptionID[selectedOptionID] {
                    response = CodexDesktopApprovalResponse(
                        requestID: pendingApproval.requestID,
                        method: pendingApproval.method,
                        result: result,
                        submission: submission(for: pendingApproval, result: result)
                    )
                } else {
                    let feedbackPlan = feedbackFollowUpPlan(
                        for: pendingApproval,
                        followUp: followUp,
                        text: trimmedText
                    )
                    response = CodexDesktopApprovalResponse(
                        requestID: pendingApproval.requestID,
                        method: pendingApproval.method,
                        result: negativeResult,
                        submission: submission(for: pendingApproval, result: negativeResult),
                        followUpSubmission: feedbackPlan?.preferredSubmission,
                        fallbackFollowUpSubmission: feedbackPlan?.fallbackSubmission,
                        followUpConversationID: feedbackPlan?.conversationID
                    )
                }
            case let .userInput(questionID, optionAnswersByOptionID, isOther):
                let answer = userInputAnswer(
                    selectedOptionID: selectedOptionID,
                    optionAnswersByOptionID: optionAnswersByOptionID,
                    text: trimmedText,
                    isOther: isOther
                )
                let result = userInputResult(questionID: questionID, answer: answer)
                response = CodexDesktopApprovalResponse(
                    requestID: pendingApproval.requestID,
                    method: pendingApproval.method,
                    result: result,
                    submission: submission(for: pendingApproval, result: result)
                )
            }
        }

        self.pendingApproval = nil
        return response
    }

    func reset() -> CodexActionableSurface? {
        let surface = pendingApproval?.surface
        pendingApproval = nil
        return surface
    }

    private func makeCommandApproval(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let availableDecisions = request.params.arrayValue(at: ["availableDecisions"]) ?? [.string("accept")]
        let positiveOptions = makeOptions(
            decisions: positiveDecisions(
                from: availableDecisions,
                method: .commandExecution
            ),
            method: .commandExecution,
            request: request
        )
        let negativeResult = cancelResult(
            for: .commandExecution,
            availableDecisions: availableDecisions
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to run the following command?",
            preview: request.params.stringValue(at: ["command"]),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: positiveOptions,
            textInput: CodexSurfaceTextInput(
                text: "",
                isEditable: true
            ),
            selectionMode: .optionResultsWithOther(
                Dictionary(uniqueKeysWithValues: positiveOptions.map { ($0.option.id, $0.result) }),
                negativeResult: negativeResult,
                followUp: makeFollowUpRequest(from: request)
            ),
            cancelResult: negativeResult,
            delivery: delivery
        )
    }

    private func makeFileChangeApproval(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let decisions = request.params.arrayValue(at: ["availableDecisions"]) ?? [
            .string("accept"),
            .string("acceptForSession"),
            .string("decline"),
        ]
        let positiveOptions = makeOptions(
            decisions: positiveDecisions(
                from: decisions,
                method: .fileChange
            ),
            method: .fileChange,
            request: request
        )
        let negativeResult = cancelResult(
            for: .fileChange,
            availableDecisions: decisions
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to make the following edits?",
            preview: request.params.stringValue(at: ["grantRoot"]),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: positiveOptions,
            textInput: CodexSurfaceTextInput(
                text: "",
                isEditable: true
            ),
            selectionMode: .optionResultsWithOther(
                Dictionary(uniqueKeysWithValues: positiveOptions.map { ($0.option.id, $0.result) }),
                negativeResult: negativeResult,
                followUp: makeFollowUpRequest(from: request)
            ),
            cancelResult: negativeResult,
            delivery: delivery
        )
    }

    private func makeUserInputRequest(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let question = request.params.arrayValue(at: ["questions"])?.first?.objectValue ?? [:]
        let questionID = question.stringValue(at: ["id"]) ?? "question-0"
        let summary = question.stringValue(at: ["question"])
            ?? question.stringValue(at: ["header"])
            ?? "Codex needs your input"
        let preview: String?
        if let header = question.stringValue(at: ["header"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           header.isEmpty == false,
           header != summary {
            preview = header
        } else {
            preview = nil
        }

        let options = makeUserInputOptions(
            from: question.arrayValue(at: ["options"]) ?? [],
            request: request
        )
        let isOther = question.jsonValue(at: ["isOther"])?.boolValue ?? false
        let showsTextInput = isOther || options.isEmpty
        return makePendingApproval(
            request: request,
            summary: summary,
            preview: preview,
            threadID: request.params.stringValue(at: ["threadId"]),
            options: options.map { (option: $0.option, result: .null) },
            textInput: showsTextInput
                ? CodexSurfaceTextInput(
                    title: isOther ? nil : "Type here",
                    text: "",
                    isEditable: true
                )
                : nil,
            selectionMode: .userInput(
                questionID: questionID,
                optionAnswersByOptionID: Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.answer) }),
                isOther: isOther
            ),
            cancelResult: .object([
                "answers": .object([:]),
            ]),
            delivery: delivery
        )
    }

    private func makeLegacyCommandApproval(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let decisions: [JSONValue] = [
            .string("approved"),
            .object([
                "approved_execpolicy_amendment": .object([
                    "proposed_execpolicy_amendment": .array(
                        (request.params.arrayValue(at: ["command"]) ?? []).map { value in
                            .string(value.stringValue ?? "")
                        }
                    ),
                ]),
            ]),
            .string("approved_for_session"),
            .string("denied"),
        ]
        let options = makeOptions(
            decisions: decisions,
            method: .legacyExecCommand,
            request: request
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to run the following command?",
            preview: legacyCommandPreview(from: request.params),
            threadID: request.params.stringValue(at: ["conversationId"]),
            options: options,
            textInput: nil,
            selectionMode: .optionResults(
                Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) })
            ),
            cancelResult: .object([
                "decision": .string("abort"),
            ]),
            delivery: delivery
        )
    }

    private func makeLegacyPatchApproval(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let decisions: [JSONValue] = [
            .string("approved"),
            .string("approved_for_session"),
            .string("denied"),
        ]
        let options = makeOptions(
            decisions: decisions,
            method: .legacyApplyPatch,
            request: request
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to make the following edits?",
            preview: legacyPatchPreview(from: request.params),
            threadID: request.params.stringValue(at: ["conversationId"]),
            options: options,
            textInput: nil,
            selectionMode: .optionResults(
                Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) })
            ),
            cancelResult: .object([
                "decision": .string("abort"),
            ]),
            delivery: delivery
        )
    }

    private func makeOptions(
        decisions: [JSONValue],
        method: SupportedMethod,
        request: CodexDesktopIPCRequestFrame
    ) -> [(option: CodexSurfaceOption, result: JSONValue)] {
        let surfaceID = surfaceID(for: request)
        return decisions.enumerated().compactMap { index, decision in
            makeOption(
                decision: decision,
                method: method,
                surfaceID: surfaceID,
                index: index,
                params: request.params
            )
        }
    }

    private func makePendingApproval(
        request: CodexDesktopIPCRequestFrame,
        summary: String,
        preview: String?,
        threadID: String?,
        options: [(option: CodexSurfaceOption, result: JSONValue)],
        textInput: CodexSurfaceTextInput?,
        selectionMode: SelectionMode,
        cancelResult: JSONValue,
        delivery: Delivery
    ) -> PendingApproval {
        let surfaceID = surfaceID(for: request)
        let followUpDelivery = liveDelivery(for: request) ?? delivery

        return PendingApproval(
            requestID: request.requestID,
            rawRequestID: request.rawRequestID ?? .string(request.requestID),
            method: request.method,
            selectionMode: selectionMode,
            cancelResult: cancelResult,
            delivery: delivery,
            followUpDelivery: followUpDelivery,
            surface: CodexActionableSurface(
                id: surfaceID,
                summary: summary,
                commandPreview: preview,
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip",
                options: options.map(\.option),
                textInput: textInput,
                threadID: threadID
            )
        )
    }

    private func liveDelivery(for request: CodexDesktopIPCRequestFrame) -> Delivery? {
        guard let method = SupportedMethod(rawValue: request.method) else {
            return nil
        }

        switch method {
        case .commandExecution, .fileChange, .toolRequestUserInput:
            guard let conversationID = request.params.stringValue(at: ["threadId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  conversationID.isEmpty == false
            else {
                return nil
            }

            let ownerClientID = request.sourceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ownerClientID.isEmpty == false else {
                return nil
            }

            return .threadFollower(ownerClientID: ownerClientID, conversationID: conversationID, version: 1)
        case .legacyExecCommand, .legacyApplyPatch:
            return nil
        }
    }

    private func submission(
        for pendingApproval: PendingApproval,
        result: JSONValue
    ) -> CodexDesktopApprovalSubmission {
        switch pendingApproval.delivery {
        case .response:
            return .response
        case let .threadFollower(ownerClientID, conversationID, version):
            switch pendingApproval.method {
            case SupportedMethod.commandExecution.rawValue:
                guard let decision = result.objectValue?["decision"] else {
                    return .response
                }
                return .request(
                    method: "thread-follower-command-approval-decision",
                    params: [
                        "conversationId": .string(conversationID),
                        "requestId": pendingApproval.rawRequestID,
                        "decision": decision,
                    ],
                    targetClientID: ownerClientID,
                    version: version
                )
            case SupportedMethod.fileChange.rawValue:
                guard let decision = result.objectValue?["decision"] else {
                    return .response
                }
                return .request(
                    method: "thread-follower-file-approval-decision",
                    params: [
                        "conversationId": .string(conversationID),
                        "requestId": pendingApproval.rawRequestID,
                        "decision": decision,
                    ],
                    targetClientID: ownerClientID,
                    version: version
                )
            case SupportedMethod.toolRequestUserInput.rawValue:
                return .request(
                    method: "thread-follower-submit-user-input",
                    params: [
                        "conversationId": .string(conversationID),
                        "requestId": pendingApproval.rawRequestID,
                        "response": result,
                    ],
                    targetClientID: ownerClientID,
                    version: version
                )
            default:
                return .response
            }
        }
    }

    private func cancelResult(
        for method: SupportedMethod,
        availableDecisions: [JSONValue]
    ) -> JSONValue {
        let decision: JSONValue
        switch method {
        case .commandExecution, .fileChange:
            let preferredNegativeDecisions = ["decline", "cancel"]
            if let matched = preferredNegativeDecisions.compactMap({ candidate in
                availableDecisions.first(where: { $0.stringValue == candidate })
            }).first {
                decision = matched
            } else {
                decision = .string("decline")
            }
        case .toolRequestUserInput:
            decision = .null
        case .legacyExecCommand, .legacyApplyPatch:
            decision = .string("abort")
        }

        return .object([
            "decision": decision,
        ])
    }

    private func surfaceID(for request: CodexDesktopIPCRequestFrame) -> String {
        "codex-ipc-\(request.requestID)"
    }

    private func makeOption(
        decision: JSONValue,
        method: SupportedMethod,
        surfaceID: String,
        index: Int,
        params: [String: JSONValue]
    ) -> (option: CodexSurfaceOption, result: JSONValue)? {
        guard let title = optionTitle(for: decision, method: method, params: params) else {
            return nil
        }

        let optionID = "\(surfaceID)-option-\(index)"
        return (
            option: CodexSurfaceOption(
                id: optionID,
                index: index + 1,
                title: title,
                isSelected: index == 0
            ),
            result: .object([
                "decision": decision,
            ])
        )
    }

    private func optionTitle(
        for decision: JSONValue,
        method: SupportedMethod,
        params: [String: JSONValue]
    ) -> String? {
        if let rawDecision = decision.stringValue {
            switch (method, rawDecision) {
            case (_, "accept"), (_, "approved"):
                return "Yes"
            case (.commandExecution, "acceptForSession"):
                return "Yes, and don't ask again for this command in this session"
            case (.legacyExecCommand, "approved_for_session"):
                return "Yes, and don't ask again for this command in this session"
            case (.fileChange, "acceptForSession"):
                return "Yes, and don't ask again for these files"
            case (.legacyApplyPatch, "approved_for_session"):
                return "Yes, and don't ask again for these files"
            case (.commandExecution, "decline"):
                return "No, continue without running it"
            case (.legacyExecCommand, "denied"):
                return "No, continue without running it"
            case (.fileChange, "decline"):
                return "No, continue without applying them"
            case (.legacyApplyPatch, "denied"):
                return "No, continue without applying them"
            case (_, "cancel"), (_, "abort"):
                return nil
            default:
                return rawDecision
            }
        }

        guard let object = decision.objectValue else {
            return nil
        }

        if let amendment = object.objectValue(at: ["acceptWithExecpolicyAmendment"]),
           let commandPrefix = commandPrefixDisplayText(
                from: amendment.arrayValue(at: ["execpolicy_amendment"]),
                params: params
           ),
           commandPrefix.isEmpty == false {
            return "Yes, and don't ask again for commands that start with `\(commandPrefix)`"
        }

        if let amendment = object.objectValue(at: ["approved_execpolicy_amendment"]),
           let commandPrefix = commandPrefixDisplayText(
                from: amendment.arrayValue(at: ["proposed_execpolicy_amendment"]),
                params: params
           ),
           commandPrefix.isEmpty == false {
            return "Yes, and don't ask again for commands that start with `\(commandPrefix)`"
        }

        if let amendment = object.objectValue(at: ["applyNetworkPolicyAmendment"]),
           let host = amendment.stringValue(at: ["network_policy_amendment", "host"]) {
            return "Yes, and allow \(host) in the future"
        }

        if params.objectValue(at: ["networkApprovalContext"]) != nil {
            return "Yes, and allow this host in the future"
        }

        return nil
    }

    private func commandPrefixDisplayText(
        from amendmentValues: [JSONValue]?,
        params: [String: JSONValue]
    ) -> String? {
        let proposedComponents = params.arrayValue(at: ["proposedExecpolicyAmendment"])?.compactMap(\.stringValue) ?? []
        let amendmentComponents = amendmentValues?.compactMap(\.stringValue) ?? []

        for components in [proposedComponents, amendmentComponents] where components.isEmpty == false {
            guard let displayText = commandPrefixDisplayText(from: components, params: params) else {
                continue
            }

            return displayText
        }

        if let command = params.stringValue(at: ["command"]) {
            let displayText = CommandDisplayText.userVisibleCommand(command)
            if displayText.isEmpty == false {
                return displayText
            }
        }

        return commandPrefixDisplayText(from: amendmentComponents)
    }

    private func commandPrefixDisplayText(from components: [String], params: [String: JSONValue]) -> String? {
        if componentsStartWithShellExecutable(components),
           let rawCommand = params.stringValue(at: ["command"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           rawCommand.isEmpty == false {
            return rawCommand
        }

        return commandPrefixDisplayText(from: components)
    }

    private func commandPrefixDisplayText(from components: [String]) -> String? {
        let joinedCommand = components
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard joinedCommand.isEmpty == false else {
            return nil
        }

        return joinedCommand
    }

    private func componentsStartWithShellExecutable(_ components: [String]) -> Bool {
        guard let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let executable = firstComponent.split(separator: "/").last else {
            return false
        }

        return ["bash", "sh", "zsh"].contains(String(executable))
    }

    private func makeUserInputOptions(
        from options: [JSONValue],
        request: CodexDesktopIPCRequestFrame
    ) -> [(option: CodexSurfaceOption, answer: String)] {
        let surfaceID = surfaceID(for: request)
        return options.enumerated().compactMap { index, optionValue in
            guard let option = optionValue.objectValue else {
                return nil
            }

            let label = option.stringValue(at: ["label"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = option.stringValue(at: ["description"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = label.isEmpty ? (description ?? "") : label
            guard title.isEmpty == false else {
                return nil
            }

            return (
                option: CodexSurfaceOption(
                    id: "\(surfaceID)-option-\(index)",
                    index: index + 1,
                    title: title,
                    isSelected: index == 0
                ),
                answer: title
            )
        }
    }

    private func positiveDecisions(
        from decisions: [JSONValue],
        method: SupportedMethod
    ) -> [JSONValue] {
        decisions.filter { isNegativeDecision($0, method: method) == false }
    }

    private func isNegativeDecision(
        _ decision: JSONValue,
        method: SupportedMethod
    ) -> Bool {
        guard let rawDecision = decision.stringValue else {
            return false
        }

        switch method {
        case .commandExecution, .fileChange:
            return rawDecision == "decline" || rawDecision == "cancel"
        case .toolRequestUserInput:
            return false
        case .legacyExecCommand, .legacyApplyPatch:
            return rawDecision == "denied" || rawDecision == "abort"
        }
    }

    private func shouldClearSelectionOnTextUpdate(for selectionMode: SelectionMode) -> Bool {
        switch selectionMode {
        case .optionResults:
            return false
        case .optionResultsWithOther:
            return true
        case let .userInput(_, _, isOther):
            return isOther
        }
    }

    private func surfaceByClearingSelection(_ surface: CodexActionableSurface) -> CodexActionableSurface {
        CodexActionableSurface(
            id: surface.id,
            summary: surface.summary,
            commandPreview: surface.commandPreview,
            primaryButtonTitle: surface.primaryButtonTitle,
            cancelButtonTitle: surface.cancelButtonTitle,
            options: surface.options.map { option in
                CodexSurfaceOption(
                    id: option.id,
                    index: option.index,
                    title: option.title,
                    isSelected: false
                )
            },
            textInput: surface.textInput,
            threadID: surface.threadID,
            threadTitle: surface.threadTitle
        )
    }

    private func normalizedInputText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return nil
        }

        return text
    }

    private func userInputAnswer(
        selectedOptionID: String?,
        optionAnswersByOptionID: [String: String],
        text: String?,
        isOther: Bool
    ) -> String? {
        if let selectedOptionID,
           let selectedAnswer = optionAnswersByOptionID[selectedOptionID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           selectedAnswer.isEmpty == false {
            return selectedAnswer
        }

        if optionAnswersByOptionID.isEmpty || isOther {
            return text
        }

        return nil
    }

    private func userInputResult(questionID: String, answer: String?) -> JSONValue {
        guard let answer else {
            return .object([
                "answers": .object([:]),
            ])
        }

        return .object([
            "answers": .object([
                questionID: .object([
                    "answers": .array([
                        .string(answer),
                    ]),
                ]),
            ]),
        ])
    }

    private func feedbackFollowUpPlan(
        for pendingApproval: PendingApproval,
        followUp: FollowUpRequest?,
        text: String?
    ) -> FeedbackFollowUpPlan? {
        guard let followUp,
              let text else {
            return nil
        }

        switch pendingApproval.followUpDelivery {
        case .response:
            let textInputItems = inputItems(for: text)
            let cwd: JSONValue = followUp.cwd.map { .string($0) } ?? .null
            let startTurnParams: [String: JSONValue] = [
                "threadId": .string(followUp.threadID),
                "input": .array(textInputItems),
                "cwd": cwd,
                "approvalPolicy": .null,
                "approvalsReviewer": .string("user"),
                "sandboxPolicy": .null,
                "model": .null,
                "serviceTier": .null,
                "effort": .null,
                "summary": .string("none"),
                "personality": .null,
                "outputSchema": .null,
                "collaborationMode": .null,
                "attachments": .array([]),
            ]
            let startTurnSubmission: CodexDesktopApprovalSubmission = .request(
                method: "turn/start",
                params: startTurnParams,
                targetClientID: nil,
                version: 1
            )

            guard let turnID = followUp.turnID else {
                return FeedbackFollowUpPlan(
                    preferredSubmission: startTurnSubmission,
                    fallbackSubmission: nil,
                    conversationID: followUp.threadID
                )
            }

            let steerParams: [String: JSONValue] = [
                "threadId": .string(followUp.threadID),
                "input": .array(textInputItems),
                "expectedTurnId": turnID,
            ]
            return FeedbackFollowUpPlan(
                preferredSubmission: .request(
                    method: "turn/steer",
                    params: steerParams,
                    targetClientID: nil,
                    version: 1
                ),
                fallbackSubmission: startTurnSubmission,
                conversationID: followUp.threadID
            )
        case let .threadFollower(ownerClientID, conversationID, version):
            let textInputItems = inputItems(for: text)
            let cwd: JSONValue = followUp.cwd.map { .string($0) } ?? .null
            let restoreMessage = feedbackRestoreMessage(
                prompt: text,
                requestID: pendingApproval.requestID,
                cwd: followUp.cwd
            )
            let steerParams: [String: JSONValue] = [
                "conversationId": .string(conversationID),
                "input": .array(textInputItems),
                "attachments": .array([]),
                "restoreMessage": restoreMessage,
            ]
            let startTurnParams: [String: JSONValue] = [
                "conversationId": .string(conversationID),
                "turnStartParams": .object([
                    "input": .array(textInputItems),
                    "cwd": cwd,
                    "model": .null,
                    "effort": .null,
                    "approvalPolicy": .null,
                    "approvalsReviewer": .string("user"),
                    "sandboxPolicy": .null,
                    "attachments": .array([]),
                    "collaborationMode": .null,
                ]),
            ]
            return FeedbackFollowUpPlan(
                preferredSubmission: .request(
                    method: "thread-follower-steer-turn",
                    params: steerParams,
                    targetClientID: ownerClientID,
                    version: version
                ),
                fallbackSubmission: .request(
                    method: "thread-follower-start-turn",
                    params: startTurnParams,
                    targetClientID: ownerClientID,
                    version: version
                ),
                conversationID: conversationID
            )
        }
    }

    private func makeFollowUpRequest(from request: CodexDesktopIPCRequestFrame) -> FollowUpRequest? {
        guard let threadID = request.params.stringValue(at: ["threadId"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              threadID.isEmpty == false else {
            return nil
        }

        return FollowUpRequest(
            threadID: threadID,
            turnID: request.params.jsonValue(at: ["turnId"]),
            cwd: request.params.stringValue(at: ["cwd"])
        )
    }

    private func inputItems(for text: String) -> [JSONValue] {
        [
            .object([
                "type": .string("text"),
                "text": .string(text),
                "text_elements": .array([]),
            ]),
        ]
    }

    private func feedbackRestoreMessage(
        prompt: String,
        requestID: String,
        cwd: String?
    ) -> JSONValue {
        let workspaceRoots: [JSONValue]
        if let cwd,
           cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            workspaceRoots = [.string(cwd)]
        } else {
            workspaceRoots = []
        }

        return .object([
            "id": .string("approval-follow-up-\(requestID)"),
            "text": .string(prompt),
            "context": .object([
                "prompt": .string(prompt),
                "addedFiles": .array([]),
                "collaborationMode": .null,
                "ideContext": .null,
                "imageAttachments": .array([]),
                "fileAttachments": .array([]),
                "commentAttachments": .array([]),
                "pullRequestChecks": .array([]),
                "reviewFindings": .array([]),
                "priorConversation": .null,
                "workspaceRoots": .array(workspaceRoots),
            ]),
            "cwd": cwd.map(JSONValue.string) ?? .null,
            "createdAt": .integer(followUpCreatedAtMillisecondsProvider()),
        ])
    }

    private func legacyCommandPreview(from params: [String: JSONValue]) -> String? {
        let components = params.arrayValue(at: ["command"])?.compactMap(\.stringValue) ?? []
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    private func legacyPatchPreview(from params: [String: JSONValue]) -> String? {
        if let grantRoot = params.stringValue(at: ["grantRoot"]), grantRoot.isEmpty == false {
            return grantRoot
        }

        guard let fileChanges = params.objectValue(at: ["fileChanges"]) else {
            return nil
        }

        for (path, change) in fileChanges.sorted(by: { $0.key < $1.key }) {
            if let unifiedDiff = change.objectValue?.stringValue(at: ["unified_diff"]), unifiedDiff.isEmpty == false {
                return unifiedDiff
            }
            if let content = change.objectValue?.stringValue(at: ["content"]), content.isEmpty == false {
                return "\(path)\n\(content)"
            }
        }

        return nil
    }
}

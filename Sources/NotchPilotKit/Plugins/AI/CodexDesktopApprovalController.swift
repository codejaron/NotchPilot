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
    private typealias Delivery = CodexDesktopApprovalDelivery
    private typealias SupportedMethod = CodexDesktopApprovalMethod

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
        let conversationID: String?
        let selectionMode: SelectionMode
        let cancelResult: JSONValue
        let delivery: Delivery
        let followUpDelivery: Delivery
        var surface: CodexActionableSurface
    }

    private var pendingApprovals: [String: PendingApproval] = [:]
    private var pendingSurfaceOrder: [String] = []
    private let followUpCreatedAtMillisecondsProvider: @Sendable () -> Int

    init(
        followUpCreatedAtMillisecondsProvider: @escaping @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970 * 1000)
        }
    ) {
        self.followUpCreatedAtMillisecondsProvider = followUpCreatedAtMillisecondsProvider
    }

    var currentSurface: CodexActionableSurface? {
        pendingSurfaceOrder.reversed().compactMap {
            pendingApprovals[$0]?.surface
        }.first
    }

    static func canHandle(_ request: CodexDesktopIPCRequestFrame?) -> Bool {
        CodexDesktopApprovalRequestRouter.canHandle(request)
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
        guard let method = CodexDesktopApprovalRequestRouter.method(for: request) else {
            return nil
        }

        let pendingApproval: PendingApproval
        switch method {
        case .commandExecution:
            pendingApproval = makeCommandApproval(from: request, delivery: delivery)
        case .fileChange:
            pendingApproval = makeFileChangeApproval(from: request, delivery: delivery)
        case .permissions:
            pendingApproval = makePermissionsApproval(from: request, delivery: delivery)
        case .toolRequestUserInput:
            pendingApproval = makeUserInputRequest(from: request, delivery: delivery)
        case .mcpServerElicitation:
            guard CodexDesktopApprovalRequestRouter.isMCPToolApprovalElicitation(params: request.params) else {
                return nil
            }
            pendingApproval = makeMCPToolApprovalElicitation(from: request, delivery: delivery)
        }

        store(pendingApproval)
        return pendingApproval.surface
    }

    func selectOption(_ optionID: String, on surfaceID: String) -> CodexActionableSurface? {
        guard var pendingApproval = pendingApprovals[surfaceID],
              pendingApproval.surface.options.contains(where: { $0.id == optionID })
        else {
            return nil
        }

        pendingApproval.surface = pendingApproval.surface.selectingOption(optionID)
        pendingApprovals[surfaceID] = pendingApproval
        return pendingApproval.surface
    }

    func updateText(_ text: String, on surfaceID: String) -> CodexActionableSurface? {
        guard var pendingApproval = pendingApprovals[surfaceID],
              pendingApproval.surface.textInput != nil
        else {
            return nil
        }

        let updatedSurface = pendingApproval.surface.updatingText(text)
        pendingApproval.surface = shouldClearSelectionOnTextUpdate(for: pendingApproval.selectionMode)
            ? surfaceByClearingSelection(updatedSurface)
            : updatedSurface
        pendingApprovals[surfaceID] = pendingApproval
        return pendingApproval.surface
    }

    func perform(action: CodexSurfaceAction, on surfaceID: String) -> CodexDesktopApprovalResponse? {
        guard let pendingApproval = pendingApprovals[surfaceID] else {
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

        removePendingApproval(surfaceID: surfaceID)
        return response
    }

    func reset() -> CodexActionableSurface? {
        let surface = currentSurface
        pendingApprovals.removeAll()
        pendingSurfaceOrder.removeAll()
        return surface
    }

    func reset(conversationID: String) {
        let surfaceIDs = pendingApprovals.values.compactMap { pendingApproval in
            pendingApproval.conversationID == conversationID ? pendingApproval.surface.id : nil
        }
        for surfaceID in surfaceIDs {
            removePendingApproval(surfaceID: surfaceID)
        }
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
            delivery: delivery,
            quickActions: CodexSurfaceQuickActions(
                approveOptionID: optionID(in: positiveOptions, matchingDecision: "accept"),
                rejectUsesCancel: true
            )
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
            delivery: delivery,
            quickActions: CodexSurfaceQuickActions(
                approveOptionID: optionID(in: positiveOptions, matchingDecision: "accept"),
                rejectUsesCancel: true
            )
        )
    }

    private func makePermissionsApproval(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let requestedPermissions = request.params.jsonValue(at: ["permissions"]) ?? .object([:])
        let options = makeStaticOptions(
            request: request,
            titlesAndResults: [
                (
                    title: "Yes",
                    result: permissionsGrantResult(
                        permissions: requestedPermissions,
                        scope: "turn"
                    )
                ),
                (
                    title: "Yes, for this session",
                    result: permissionsGrantResult(
                        permissions: requestedPermissions,
                        scope: "session"
                    )
                ),
            ]
        )

        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"])
                ?? "Codex is requesting additional permissions.",
            preview: permissionsPreview(
                from: requestedPermissions,
                cwd: request.params.stringValue(at: ["cwd"])
            ),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: options,
            textInput: nil,
            selectionMode: .optionResults(
                Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) })
            ),
            cancelResult: emptyPermissionsGrantResult(),
            delivery: delivery,
            quickActions: CodexSurfaceQuickActions(
                approveOptionID: options.first?.option.id,
                rejectUsesCancel: true
            )
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

    private func makeMCPToolApprovalElicitation(
        from request: CodexDesktopIPCRequestFrame,
        delivery: Delivery
    ) -> PendingApproval {
        let options = makeMCPToolApprovalOptions(from: request)

        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["message"])
                ?? "Codex is requesting MCP tool approval.",
            preview: mcpElicitationPreview(from: request.params),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: options,
            textInput: nil,
            selectionMode: .optionResults(
                Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) })
            ),
            cancelResult: mcpElicitationResult(action: "decline"),
            delivery: delivery,
            quickActions: CodexSurfaceQuickActions(
                approveOptionID: mcpAcceptOptionID(in: options),
                rejectUsesCancel: true
            ),
            primaryButtonTitle: "Allow",
            cancelButtonTitle: "Cancel",
            showsActionButtons: false
        )
    }

    private func makeMCPToolApprovalOptions(
        from request: CodexDesktopIPCRequestFrame
    ) -> [(option: CodexSurfaceOption, result: JSONValue)] {
        var titlesAndResults: [(title: String, result: JSONValue)] = [
            (
                title: "Allow",
                result: mcpElicitationResult(action: "accept")
            ),
        ]

        for persistence in advertisedMCPToolApprovalPersistence(from: request.params) {
            titlesAndResults.append(
                (
                    title: mcpToolApprovalPersistenceTitle(persistence),
                    result: mcpElicitationResult(
                        action: "accept",
                        meta: .object([
                            "persist": .string(persistence),
                        ])
                    )
                )
            )
        }
        titlesAndResults.append(
            (
                title: "Cancel",
                result: mcpElicitationResult(action: "decline")
            )
        )

        return makeStaticOptions(request: request, titlesAndResults: titlesAndResults)
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

    private func makeStaticOptions(
        request: CodexDesktopIPCRequestFrame,
        titlesAndResults: [(title: String, result: JSONValue)]
    ) -> [(option: CodexSurfaceOption, result: JSONValue)] {
        let surfaceID = surfaceID(for: request)
        return titlesAndResults.enumerated().map { index, item in
            (
                option: CodexSurfaceOption(
                    id: "\(surfaceID)-option-\(index)",
                    index: index + 1,
                    title: item.title,
                    isSelected: index == 0
                ),
                result: item.result
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
        delivery: Delivery,
        quickActions: CodexSurfaceQuickActions = .none,
        primaryButtonTitle: String = "Submit",
        cancelButtonTitle: String = "Skip",
        showsActionButtons: Bool = true
    ) -> PendingApproval {
        let surfaceID = surfaceID(for: request)
        let followUpDelivery = liveDelivery(for: request) ?? delivery

        return PendingApproval(
            requestID: request.requestID,
            rawRequestID: request.rawRequestID ?? .string(request.requestID),
            method: request.method,
            conversationID: conversationID(threadID: threadID, delivery: delivery),
            selectionMode: selectionMode,
            cancelResult: cancelResult,
            delivery: delivery,
            followUpDelivery: followUpDelivery,
            surface: CodexActionableSurface(
                id: surfaceID,
                summary: summary,
                commandPreview: preview,
                primaryButtonTitle: primaryButtonTitle,
                cancelButtonTitle: cancelButtonTitle,
                showsActionButtons: showsActionButtons,
                options: options.map(\.option),
                textInput: textInput,
                threadID: threadID,
                quickActions: quickActions
            )
        )
    }

    private func store(_ pendingApproval: PendingApproval) {
        let surfaceID = pendingApproval.surface.id
        pendingApprovals[surfaceID] = pendingApproval
        pendingSurfaceOrder.removeAll { $0 == surfaceID }
        pendingSurfaceOrder.append(surfaceID)
    }

    private func removePendingApproval(surfaceID: String) {
        pendingApprovals.removeValue(forKey: surfaceID)
        pendingSurfaceOrder.removeAll { $0 == surfaceID }
    }

    private func conversationID(threadID: String?, delivery: Delivery) -> String? {
        switch delivery {
        case .response:
            return threadID
        case let .threadFollower(_, conversationID, _):
            return conversationID
        }
    }

    private func liveDelivery(for request: CodexDesktopIPCRequestFrame) -> Delivery? {
        CodexDesktopApprovalRequestRouter.liveDelivery(for: request)
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
            case SupportedMethod.permissions.rawValue:
                return .request(
                    method: "thread-follower-permissions-request-approval-response",
                    params: [
                        "conversationId": .string(conversationID),
                        "requestId": pendingApproval.rawRequestID,
                        "response": result,
                    ],
                    targetClientID: ownerClientID,
                    version: version
                )
            case SupportedMethod.mcpServerElicitation.rawValue:
                return .request(
                    method: "thread-follower-submit-mcp-server-elicitation-response",
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
        case .permissions:
            return emptyPermissionsGrantResult()
        case .toolRequestUserInput:
            decision = .null
        case .mcpServerElicitation:
            return mcpElicitationResult(action: "decline")
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

    private func optionID(
        in options: [(option: CodexSurfaceOption, result: JSONValue)],
        matchingDecision decision: String
    ) -> String? {
        options.first { item in
            item.result.objectValue?["decision"]?.stringValue == decision
        }?.option.id
    }

    private func mcpAcceptOptionID(
        in options: [(option: CodexSurfaceOption, result: JSONValue)]
    ) -> String? {
        options.first { item in
            guard let object = item.result.objectValue else {
                return false
            }

            return object["action"]?.stringValue == "accept"
                && (object["_meta"] == nil || object["_meta"] == .null)
        }?.option.id
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
            case (.fileChange, "acceptForSession"):
                return "Yes, and don't ask again for these files"
            case (.commandExecution, "decline"):
                return "No, continue without running it"
            case (.fileChange, "decline"):
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
        case .permissions:
            return false
        case .toolRequestUserInput:
            return false
        case .mcpServerElicitation:
            return false
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
            showsActionButtons: surface.showsActionButtons,
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
            threadTitle: surface.threadTitle,
            quickActions: surface.quickActions
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

    private func permissionsGrantResult(
        permissions: JSONValue,
        scope: String
    ) -> JSONValue {
        .object([
            "permissions": permissions,
            "scope": .string(scope),
        ])
    }

    private func emptyPermissionsGrantResult() -> JSONValue {
        permissionsGrantResult(permissions: .object([:]), scope: "turn")
    }

    private func permissionsPreview(
        from permissions: JSONValue,
        cwd: String?
    ) -> String? {
        guard let object = permissions.objectValue else {
            return normalizedInputText(cwd)
        }

        var lines: [String] = []
        if let fileSystem = object["fileSystem"]?.objectValue {
            let fileTargets = ["write", "read", "readWrite"]
                .flatMap { key in
                    fileSystem[key]?.arrayValue?.compactMap(\.stringValue) ?? []
                }
            if fileTargets.isEmpty == false {
                lines.append("Files: \(fileTargets.joined(separator: ", "))")
            }
        }

        if object["network"]?.objectValue?["enabled"]?.boolValue == true {
            lines.append("Network: enabled")
        }

        if lines.isEmpty {
            return normalizedInputText(cwd)
        }

        return lines.joined(separator: "\n")
    }

    private func mcpElicitationResult(
        action: String,
        meta: JSONValue? = nil
    ) -> JSONValue {
        .object([
            "action": .string(action),
            "content": action == "accept" ? .object([:]) : .null,
            "_meta": meta ?? .null,
        ])
    }

    private func advertisedMCPToolApprovalPersistence(from params: [String: JSONValue]) -> [String] {
        let persistValues = [
            params.jsonValue(at: ["_meta", "persist"]),
            params.jsonValue(at: ["meta", "persist"]),
        ]

        var seen = Set<String>()
        var scopes: [String] = []
        for value in persistValues {
            for scope in mcpToolApprovalPersistenceValues(from: value) {
                guard seen.insert(scope).inserted else {
                    continue
                }
                scopes.append(scope)
            }
        }

        return scopes
    }

    private func mcpToolApprovalPersistenceValues(from value: JSONValue?) -> [String] {
        let rawValues: [String]
        switch value {
        case let .string(rawValue):
            rawValues = [rawValue]
        case let .array(values):
            rawValues = values.compactMap(\.stringValue)
        default:
            rawValues = []
        }

        return rawValues.filter { $0 == "session" || $0 == "always" }
    }

    private func mcpToolApprovalPersistenceTitle(_ persistence: String) -> String {
        switch persistence {
        case "session":
            return "Allow for this chat"
        case "always":
            return "Always allow"
        default:
            return "Allow"
        }
    }

    private func mcpElicitationPreview(from params: [String: JSONValue]) -> String? {
        var lines: [String] = []
        let serverName = normalizedInputText(params.stringValue(at: ["serverName"]))
        if let serverName {
            lines.append("MCP server: \(serverName)")
        } else if let url = normalizedInputText(params.stringValue(at: ["url"])) {
            lines.append(url)
        }

        if let url = normalizedInputText(params.stringValue(at: ["url"])),
           serverName != nil {
            lines.append(url)
        }

        let toolParameters = params.objectValue(at: ["_meta", "tool_params"])
            ?? params.objectValue(at: ["meta", "tool_params"])
        if let toolParameters {
            for (name, value) in toolParameters.sorted(by: { $0.key < $1.key }) {
                lines.append("\(name): \(mcpPreviewText(for: value))")
            }
        }

        guard lines.isEmpty == false else {
            return nil
        }
        return lines.joined(separator: "\n")
    }

    private func mcpPreviewText(for value: JSONValue) -> String {
        switch value {
        case let .string(text):
            return text
        case let .integer(number):
            return "\(number)"
        case let .double(number):
            return "\(number)"
        case let .bool(flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .array, .object:
            guard JSONSerialization.isValidJSONObject(value.jsonObject),
                  let data = try? JSONSerialization.data(
                    withJSONObject: value.jsonObject,
                    options: [.sortedKeys]
                  ),
                  let text = String(data: data, encoding: .utf8)
            else {
                return String(describing: value.jsonObject)
            }
            return text
        }
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

}

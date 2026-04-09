import Foundation

enum CodexDesktopApprovalSubmission: Equatable, Sendable {
    case response
    case request(
        method: String,
        params: [String: JSONValue],
        targetClientID: String,
        version: Int
    )
}

struct CodexDesktopApprovalResponse: Equatable, Sendable {
    let requestID: String
    let method: String
    let result: JSONValue
    let submission: CodexDesktopApprovalSubmission
}

final class CodexDesktopApprovalController {
    private enum Delivery: Equatable {
        case response
        case threadFollower(ownerClientID: String, conversationID: String, version: Int)
    }

    private struct PendingApproval {
        let requestID: String
        let rawRequestID: JSONValue
        let method: String
        let responsesByOptionID: [String: JSONValue]
        let cancelResult: JSONValue
        let delivery: Delivery
        var surface: CodexActionableSurface
    }

    private enum SupportedMethod: String {
        case commandExecution = "item/commandExecution/requestApproval"
        case fileChange = "item/fileChange/requestApproval"
        case legacyExecCommand = "execCommandApproval"
        case legacyApplyPatch = "applyPatchApproval"
    }

    private var pendingApproval: PendingApproval?

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
              pendingApproval.responsesByOptionID[optionID] != nil
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

        pendingApproval.surface = pendingApproval.surface.updatingText(text)
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
                ?? pendingApproval.surface.options.first?.id
            guard let selectedOptionID,
                  let result = pendingApproval.responsesByOptionID[selectedOptionID]
            else {
                return nil
            }

            response = CodexDesktopApprovalResponse(
                requestID: pendingApproval.requestID,
                method: pendingApproval.method,
                result: result,
                submission: submission(for: pendingApproval, result: result)
            )
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
        let options = makeOptions(
            decisions: availableDecisions,
            method: .commandExecution,
            request: request
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to run the following command?",
            preview: request.params.stringValue(at: ["command"]),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: options,
            cancelResult: cancelResult(
                for: .commandExecution,
                availableDecisions: availableDecisions
            ),
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
        let options = makeOptions(
            decisions: decisions,
            method: .fileChange,
            request: request
        )
        return makePendingApproval(
            request: request,
            summary: request.params.stringValue(at: ["reason"]) ?? "Would you like to make the following edits?",
            preview: request.params.stringValue(at: ["grantRoot"]),
            threadID: request.params.stringValue(at: ["threadId"]),
            options: options,
            cancelResult: cancelResult(
                for: .fileChange,
                availableDecisions: decisions
            ),
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
        cancelResult: JSONValue,
        delivery: Delivery
    ) -> PendingApproval {
        let surfaceID = surfaceID(for: request)

        return PendingApproval(
            requestID: request.requestID,
            rawRequestID: request.rawRequestID ?? .string(request.requestID),
            method: request.method,
            responsesByOptionID: Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) }),
            cancelResult: cancelResult,
            delivery: delivery,
            surface: CodexActionableSurface(
                id: surfaceID,
                summary: summary,
                commandPreview: preview,
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip",
                options: options.map(\.option),
                threadID: threadID
            )
        )
    }

    private func liveDelivery(for request: CodexDesktopIPCRequestFrame) -> Delivery? {
        guard let method = SupportedMethod(rawValue: request.method) else {
            return nil
        }

        switch method {
        case .commandExecution, .fileChange:
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
            guard let requestMethod = threadFollowerMethod(for: pendingApproval.method),
                  let decision = result.objectValue?["decision"]
            else {
                return .response
            }

            return .request(
                method: requestMethod,
                params: [
                    "conversationId": .string(conversationID),
                    "requestId": pendingApproval.rawRequestID,
                    "decision": decision,
                ],
                targetClientID: ownerClientID,
                version: version
            )
        }
    }

    private func threadFollowerMethod(for approvalMethod: String) -> String? {
        switch approvalMethod {
        case SupportedMethod.commandExecution.rawValue:
            "thread-follower-command-approval-decision"
        case SupportedMethod.fileChange.rawValue:
            "thread-follower-file-approval-decision"
        default:
            nil
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
           let commandPrefix = amendment.arrayValue(at: ["execpolicy_amendment"])?.compactMap(\.stringValue).first,
           commandPrefix.isEmpty == false {
            return "Yes, and don't ask again for commands that start with `\(commandPrefix)`"
        }

        if let amendment = object.objectValue(at: ["approved_execpolicy_amendment"]),
           let commandPrefix = amendment.arrayValue(at: ["proposed_execpolicy_amendment"])?.compactMap(\.stringValue).joined(separator: " "),
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

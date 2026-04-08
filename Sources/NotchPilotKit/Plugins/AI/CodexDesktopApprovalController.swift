import Foundation

struct CodexDesktopApprovalResponse: Equatable, Sendable {
    let requestID: String
    let method: String
    let result: JSONValue
}

final class CodexDesktopApprovalController {
    private struct PendingApproval {
        let requestID: String
        let method: String
        let responsesByOptionID: [String: JSONValue]
        let cancelResult: JSONValue
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
        guard let method = SupportedMethod(rawValue: request.method) else {
            return nil
        }

        let pendingApproval: PendingApproval
        switch method {
        case .commandExecution:
            pendingApproval = makeCommandApproval(from: request)
        case .fileChange:
            pendingApproval = makeFileChangeApproval(from: request)
        case .legacyExecCommand:
            pendingApproval = makeLegacyCommandApproval(from: request)
        case .legacyApplyPatch:
            pendingApproval = makeLegacyPatchApproval(from: request)
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
                result: pendingApproval.cancelResult
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
                result: result
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

    private func makeCommandApproval(from request: CodexDesktopIPCRequestFrame) -> PendingApproval {
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
            cancelDecision: "cancel"
        )
    }

    private func makeFileChangeApproval(from request: CodexDesktopIPCRequestFrame) -> PendingApproval {
        let decisions: [JSONValue] = [
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
            cancelDecision: "cancel"
        )
    }

    private func makeLegacyCommandApproval(from request: CodexDesktopIPCRequestFrame) -> PendingApproval {
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
            cancelDecision: "abort"
        )
    }

    private func makeLegacyPatchApproval(from request: CodexDesktopIPCRequestFrame) -> PendingApproval {
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
            cancelDecision: "abort"
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
        cancelDecision: String
    ) -> PendingApproval {
        let surfaceID = surfaceID(for: request)

        return PendingApproval(
            requestID: request.requestID,
            method: request.method,
            responsesByOptionID: Dictionary(uniqueKeysWithValues: options.map { ($0.option.id, $0.result) }),
            cancelResult: .object([
                "decision": .string(cancelDecision),
            ]),
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

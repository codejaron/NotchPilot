import Foundation

public enum CodexDesktopReducerOutput: Equatable, Sendable {
    case sessionUpsert(AISession)
    case approvalRequested(PendingApproval)
    case approvalResolved(requestID: String)
}

public struct CodexDesktopEventReducer {
    private var sessions: [String: AISession] = [:]
    private var conversationStates: [String: JSONValue] = [:]
    private var approvalRequestIDsByItemKey: [String: String] = [:]

    public init() {}

    public mutating func consume(frame: CodexDesktopIPCFrame) throws -> [CodexDesktopReducerOutput] {
        switch frame {
        case let .broadcast(broadcast):
            return consume(method: broadcast.method, params: broadcast.params, requestID: nil)
        case let .request(request):
            return consume(method: request.method, params: request.params, requestID: request.requestID)
        default:
            return []
        }
    }

    private mutating func consume(
        method: String,
        params: [String: JSONValue],
        requestID: String?
    ) -> [CodexDesktopReducerOutput] {
        switch method {
        case "thread-stream-state-changed":
            return handleThreadStreamStateChanged(params: params)
        case "item/commandExecution/requestApproval":
            guard let requestID else { return [] }
            return handleCommandApprovalRequest(requestID: requestID, params: params)
        case "item/fileChange/requestApproval":
            guard let requestID else { return [] }
            return handleFileChangeApprovalRequest(requestID: requestID, params: params)
        case "serverRequest/resolved":
            guard let resolvedRequestID = params.stringValue(at: ["requestId"]) else {
                return []
            }
            approvalRequestIDsByItemKey = approvalRequestIDsByItemKey.filter { $0.value != resolvedRequestID }
            return [.approvalResolved(requestID: resolvedRequestID)]
        default:
            return []
        }
    }

    private mutating func handleThreadStreamStateChanged(
        params: [String: JSONValue]
    ) -> [CodexDesktopReducerOutput] {
        guard
            let conversationID = params.stringValue(at: ["conversationId"]),
            let change = params.objectValue(at: ["change"]),
            let changeType = change.stringValue(at: ["type"])
        else {
            return []
        }

        switch changeType {
        case "snapshot":
            guard let conversationState = change.jsonValue(at: ["conversationState"]) else {
                return []
            }
            conversationStates[conversationID] = conversationState
        case "patches":
            guard var conversationState = conversationStates[conversationID],
                  let patches = change.arrayValue(at: ["patches"])
            else {
                return []
            }

            for patchValue in patches {
                guard let patch = patchValue.objectValue else {
                    continue
                }
                apply(patch: patch, to: &conversationState)
            }

            conversationStates[conversationID] = conversationState
        default:
            return []
        }

        guard let conversationState = conversationStates[conversationID]?.objectValue else {
            return []
        }

        return [emitConversationSession(conversationID: conversationID, state: conversationState)]
    }

    private mutating func handleCommandApprovalRequest(
        requestID: String,
        params: [String: JSONValue]
    ) -> [CodexDesktopReducerOutput] {
        guard let threadID = params.stringValue(at: ["threadId"]) else {
            return []
        }

        let itemID = params.stringValue(at: ["itemId"])
        let snapshot = itemID.flatMap { snapshotForItem(threadID: threadID, itemID: $0) }

        let networkContext = networkApprovalContext(from: params.objectValue(at: ["networkApprovalContext"]))
        let approvalKind: ApprovalKind = networkContext == nil ? .commandExecution : .networkAccess
        let command = params.stringValue(at: ["command"])
            ?? snapshot?.commandPreview
        let cwd = params.stringValue(at: ["cwd"])
            ?? snapshot?.cwd

        let previewText: String
        let toolName: String
        if let networkContext {
            toolName = "Network Access"
            let portSuffix = networkContext.port.map { ":\($0)" } ?? ""
            previewText = "\(networkContext.protocolName.uppercased()) \(networkContext.host)\(portSuffix)"
        } else {
            toolName = "Command"
            previewText = command ?? "Review the requested command."
        }

        let approval = PendingApproval(
            requestID: requestID,
            sessionID: threadID,
            host: .codex,
            approvalKind: approvalKind,
            payload: ApprovalPayload(
                title: "\(toolName) wants approval",
                toolName: toolName,
                previewText: previewText,
                command: command
            ),
            capabilities: .none,
            availableActions: ApprovalAction.codexActions(
                for: approvalKind,
                availableDecisions: params.arrayValue(at: ["availableDecisions"]),
                proposedExecpolicyAmendment: params.jsonValue(at: ["proposedExecpolicyAmendment"])
            ),
            threadID: threadID,
            turnID: params.stringValue(at: ["turnId"]),
            itemID: itemID,
            reason: params.stringValue(at: ["reason"]),
            cwd: cwd,
            networkApprovalContext: networkContext,
            status: .pending
        )

        if let itemID {
            approvalRequestIDsByItemKey[snapshotKey(threadID: threadID, itemID: itemID)] = requestID
        }

        return [
            emitSession(threadID: threadID, params: params, label: "Waiting Approval", eventType: .unknown("item/commandExecution/requestApproval")),
            .approvalRequested(approval),
        ]
    }

    private mutating func handleFileChangeApprovalRequest(
        requestID: String,
        params: [String: JSONValue]
    ) -> [CodexDesktopReducerOutput] {
        guard let threadID = params.stringValue(at: ["threadId"]) else {
            return []
        }

        let itemID = params.stringValue(at: ["itemId"])
        let snapshot = itemID.flatMap { snapshotForItem(threadID: threadID, itemID: $0) }

        let approval = PendingApproval(
            requestID: requestID,
            sessionID: threadID,
            host: .codex,
            approvalKind: .fileChange,
            payload: ApprovalPayload(
                title: "File change wants approval",
                toolName: "File Change",
                previewText: snapshot?.previewText ?? "Review the proposed file changes.",
                filePath: snapshot?.filePath,
                diffContent: snapshot?.diffContent,
                originalContent: snapshot?.originalContent
            ),
            capabilities: .none,
            availableActions: ApprovalAction.codexActions(
                for: .fileChange,
                availableDecisions: params.arrayValue(at: ["availableDecisions"]),
                proposedExecpolicyAmendment: nil
            ),
            threadID: threadID,
            turnID: params.stringValue(at: ["turnId"]),
            itemID: itemID,
            reason: params.stringValue(at: ["reason"]),
            grantRoot: params.stringValue(at: ["grantRoot"]),
            status: .pending
        )

        if let itemID {
            approvalRequestIDsByItemKey[snapshotKey(threadID: threadID, itemID: itemID)] = requestID
        }

        return [
            emitSession(threadID: threadID, params: params, label: "Waiting Approval", eventType: .unknown("item/fileChange/requestApproval")),
            .approvalRequested(approval),
        ]
    }

    private mutating func emitSession(
        threadID: String,
        params: [String: JSONValue],
        label: String,
        eventType: AIBridgeEventType,
        titleOverride: String? = nil
    ) -> CodexDesktopReducerOutput {
        var session = sessions[threadID] ?? AISession(
            id: threadID,
            host: .codex,
            lastEventType: eventType,
            activityLabel: label,
            sessionTitle: titleOverride
        )

        session.lastEventType = eventType
        session.activityLabel = label
        // Approval-related requests should not clobber thread-level cumulative token totals
        // that came from the latest conversation snapshot.

        if let threadTitle = params.stringValue(at: ["thread", "name"])
            ?? params.stringValue(at: ["threadName"])
            ?? titleOverride
        {
            session.sessionTitle = threadTitle
        }

        session.updatedAt = Date()
        sessions[threadID] = session
        return .sessionUpsert(session)
    }

    private mutating func emitConversationSession(
        conversationID: String,
        state: [String: JSONValue]
    ) -> CodexDesktopReducerOutput {
        let eventType = conversationEventType(from: state)
        var session = sessions[conversationID] ?? AISession(
            id: conversationID,
            host: .codex,
            lastEventType: eventType,
            activityLabel: conversationActivityLabel(from: state),
            sessionTitle: conversationTitle(from: state)
        )

        session.lastEventType = eventType
        session.activityLabel = conversationActivityLabel(from: state)
        session.inputTokenCount = state.integerValue(at: ["latestTokenUsageInfo", "total", "inputTokens"])
        session.outputTokenCount = state.integerValue(at: ["latestTokenUsageInfo", "total", "outputTokens"])

        if let title = conversationTitle(from: state) {
            session.sessionTitle = title
        }

        session.updatedAt = Date()
        sessions[conversationID] = session
        return .sessionUpsert(session)
    }

    private func snapshotKey(threadID: String, itemID: String) -> String {
        "\(threadID)::\(itemID)"
    }

    private func snapshotForItem(threadID: String, itemID: String) -> CodexItemSnapshot? {
        guard let state = conversationStates[threadID]?.objectValue,
              let turns = state.arrayValue(at: ["turns"])
        else {
            return nil
        }

        for turnValue in turns.reversed() {
            guard let turn = turnValue.objectValue,
                  let items = turn.arrayValue(at: ["items"])
            else {
                continue
            }

            for itemValue in items.reversed() {
                guard let item = itemValue.objectValue,
                      item.stringValue(at: ["id"]) == itemID,
                      let itemType = item.stringValue(at: ["type"])
                else {
                    continue
                }

                switch itemType {
                case "commandExecution":
                    return .command(
                        CodexCommandSnapshot(
                            command: commandPreview(from: item),
                            cwd: item.stringValue(at: ["cwd"])
                        )
                    )
                case "fileChange":
                    return .fileChange(fileChangeSnapshot(from: item))
                default:
                    continue
                }
            }
        }

        return nil
    }

    private func commandPreview(from item: [String: JSONValue]) -> String? {
        if let direct = item.stringValue(at: ["command"]) {
            return direct
        }

        if let commandArray = item.arrayValue(at: ["command"]) {
            let parts = commandArray.compactMap(\.stringValue)
            if parts.isEmpty == false {
                return parts.joined(separator: " ")
            }
        }

        if let argv = item.arrayValue(at: ["argv"]) {
            let parts = argv.compactMap(\.stringValue)
            if parts.isEmpty == false {
                return parts.joined(separator: " ")
            }
        }

        return nil
    }

    private func fileChangeSnapshot(from item: [String: JSONValue]) -> CodexFileChangeSnapshot {
        let firstChange = item.arrayValue(at: ["changes"])?.first?.objectValue
        let filePath = firstChange?.stringValue(at: ["path"])
            ?? item.stringValue(at: ["path"])
        let originalContent = firstChange?.stringValue(at: ["oldText"])
            ?? firstChange?.stringValue(at: ["oldContent"])
            ?? firstChange?.stringValue(at: ["before"])
        let newContent = firstChange?.stringValue(at: ["newText"])
            ?? firstChange?.stringValue(at: ["newContent"])
            ?? firstChange?.stringValue(at: ["after"])
        let diffContent = firstChange?.stringValue(at: ["patch"])
            ?? firstChange?.stringValue(at: ["diff"])
            ?? newContent

        return CodexFileChangeSnapshot(
            filePath: filePath,
            originalContent: originalContent,
            diffContent: diffContent,
            previewText: filePath ?? "Review the proposed file changes."
        )
    }

    private func networkApprovalContext(from object: [String: JSONValue]?) -> NetworkApprovalContext? {
        guard
            let object,
            let host = object.stringValue(at: ["host"]),
            let protocolName = object.stringValue(at: ["protocol"])
        else {
            return nil
        }

        return NetworkApprovalContext(
            host: host,
            protocolName: protocolName,
            port: object.integerValue(at: ["port"])
        )
    }

    private func sessionTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else {
            return trimmed
        }
        return String(trimmed.prefix(30)) + "…"
    }

    private func humanize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func conversationTitle(from state: [String: JSONValue]) -> String? {
        if let title = state.stringValue(at: ["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            return title
        }

        guard let turns = state.arrayValue(at: ["turns"]) else {
            return nil
        }

        for turnValue in turns.reversed() {
            guard let turn = turnValue.objectValue,
                  let items = turn.arrayValue(at: ["items"])
            else {
                continue
            }

            for itemValue in items.reversed() {
                guard let item = itemValue.objectValue,
                      item.stringValue(at: ["type"]) == "userMessage",
                      let content = item.arrayValue(at: ["content"])
                else {
                    continue
                }

                for contentValue in content {
                    guard let contentObject = contentValue.objectValue,
                          let text = contentObject.stringValue(at: ["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                          text.isEmpty == false
                    else {
                        continue
                    }
                    return sessionTitle(from: text)
                }
            }
        }

        return nil
    }

    private func conversationActivityLabel(from state: [String: JSONValue]) -> String {
        if let status = latestTurnStatus(from: state) {
            switch status {
            case "inProgress":
                return "Working"
            case "completed":
                return "Completed"
            case "interrupted":
                return "Interrupted"
            case "errored":
                return "Error"
            default:
                return humanize(status)
            }
        }

        if let runtimeStatus = state.stringValue(at: ["threadRuntimeStatus", "type"]) {
            switch runtimeStatus {
            case "loading", "running", "streaming", "inProgress":
                return "Working"
            case "notLoaded", "loaded", "idle":
                return "Connected"
            default:
                return humanize(runtimeStatus)
            }
        }

        return "Connected"
    }

    private func conversationEventType(from state: [String: JSONValue]) -> AIBridgeEventType {
        if let status = latestTurnStatus(from: state) {
            switch status {
            case "completed":
                return .postToolUse
            case "inProgress":
                return .unknown("thread-stream-state-changed/inProgress")
            default:
                return .unknown("thread-stream-state-changed/\(status)")
            }
        }

        return .sessionStart
    }

    private func latestTurnStatus(from state: [String: JSONValue]) -> String? {
        state.arrayValue(at: ["turns"])?
            .compactMap(\.objectValue)
            .last?
            .stringValue(at: ["status"])
    }

    private func apply(patch: [String: JSONValue], to state: inout JSONValue) {
        guard
            let operation = patch.stringValue(at: ["op"]),
            let rawPath = patch.arrayValue(at: ["path"]),
            let path = patchPath(from: rawPath)
        else {
            return
        }

        _ = apply(
            operation: operation,
            path: ArraySlice(path),
            value: patch["value"],
            to: &state
        )
    }

    private func patchPath(from rawPath: [JSONValue]) -> [ConversationPatchPathComponent]? {
        let components = rawPath.compactMap { component -> ConversationPatchPathComponent? in
            switch component {
            case let .integer(index):
                return .index(index)
            case let .string(key):
                return .key(key)
            default:
                return nil
            }
        }

        return components.count == rawPath.count ? components : nil
    }

    private func apply(
        operation: String,
        path: ArraySlice<ConversationPatchPathComponent>,
        value: JSONValue?,
        to node: inout JSONValue
    ) -> Bool {
        guard let component = path.first else {
            switch operation {
            case "add", "replace":
                if let value {
                    node = value
                    return true
                }
                return false
            case "remove":
                node = .null
                return true
            default:
                return false
            }
        }

        let remainingPath = path.dropFirst()

        switch component {
        case let .key(key):
            guard case var .object(object) = node else {
                return false
            }

            if remainingPath.isEmpty {
                switch operation {
                case "add", "replace":
                    object[key] = value ?? .null
                case "remove":
                    object.removeValue(forKey: key)
                default:
                    return false
                }
                node = .object(object)
                return true
            }

            var child = object[key] ?? emptyContainer(for: remainingPath.first)
            let applied = apply(operation: operation, path: remainingPath, value: value, to: &child)
            if applied {
                object[key] = child
                node = .object(object)
            }
            return applied

        case let .index(index):
            guard case var .array(array) = node else {
                return false
            }

            if remainingPath.isEmpty {
                switch operation {
                case "add":
                    guard index >= 0, index <= array.count else {
                        return false
                    }
                    array.insert(value ?? .null, at: index)
                case "replace":
                    guard index >= 0, index < array.count else {
                        return false
                    }
                    array[index] = value ?? .null
                case "remove":
                    guard index >= 0, index < array.count else {
                        return false
                    }
                    array.remove(at: index)
                default:
                    return false
                }
                node = .array(array)
                return true
            }

            guard index >= 0, index < array.count else {
                return false
            }

            var child = array[index]
            let applied = apply(operation: operation, path: remainingPath, value: value, to: &child)
            if applied {
                array[index] = child
                node = .array(array)
            }
            return applied
        }
    }

    private func emptyContainer(for component: ConversationPatchPathComponent?) -> JSONValue {
        switch component {
        case .index:
            return .array([])
        case .key, .none:
            return .object([:])
        }
    }
}

private enum ConversationPatchPathComponent {
    case key(String)
    case index(Int)
}

private enum CodexItemSnapshot {
    case command(CodexCommandSnapshot)
    case fileChange(CodexFileChangeSnapshot)

    var commandPreview: String? {
        guard case let .command(snapshot) = self else {
            return nil
        }
        return snapshot.command
    }

    var cwd: String? {
        guard case let .command(snapshot) = self else {
            return nil
        }
        return snapshot.cwd
    }

    var filePath: String? {
        guard case let .fileChange(snapshot) = self else {
            return nil
        }
        return snapshot.filePath
    }

    var originalContent: String? {
        guard case let .fileChange(snapshot) = self else {
            return nil
        }
        return snapshot.originalContent
    }

    var diffContent: String? {
        guard case let .fileChange(snapshot) = self else {
            return nil
        }
        return snapshot.diffContent
    }

    var previewText: String? {
        switch self {
        case let .command(snapshot):
            return snapshot.command
        case let .fileChange(snapshot):
            return snapshot.previewText
        }
    }
}

private struct CodexCommandSnapshot {
    let command: String?
    let cwd: String?
}

private struct CodexFileChangeSnapshot {
    let filePath: String?
    let originalContent: String?
    let diffContent: String?
    let previewText: String
}

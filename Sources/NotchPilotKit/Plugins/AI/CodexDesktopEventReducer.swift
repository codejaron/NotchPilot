import Foundation

public enum CodexDesktopReducerOutput: Equatable, Sendable {
    case threadContextUpsert(CodexThreadContext, marksActivity: Bool)
}

public struct CodexDesktopEventReducer {
    private static let titlePaths: [[String]] = [
        ["title"],
        ["metadata", "title"],
        ["metadata", "name"],
        ["threadMetadata", "title"],
        ["threadMetadata", "name"],
        ["thread", "title"],
        ["thread", "name"],
        ["threadTitle"],
        ["threadName"],
        ["name"],
    ]
    private static let conversationIDPaths: [[String]] = [
        ["conversationId"],
        ["threadId"],
        ["threadID"],
        ["id"],
        ["thread", "id"],
        ["conversation", "id"],
    ]

    private var conversationStates: [String: JSONValue] = [:]

    public init() {}

    public mutating func consume(frame: CodexDesktopIPCFrame) throws -> [CodexDesktopReducerOutput] {
        switch frame {
        case let .broadcast(broadcast):
            return consume(method: broadcast.method, params: broadcast.params)
        case let .request(request):
            return consume(method: request.method, params: request.params)
        default:
            return []
        }
    }

    private mutating func consume(
        method: String,
        params: [String: JSONValue]
    ) -> [CodexDesktopReducerOutput] {
        switch method {
        case "thread-stream-state-changed":
            return handleThreadStreamStateChanged(params: params)
        case "thread/metadata/update":
            return handleThreadMetadataUpdate(params: params)
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
            return outputForConversationState(conversationID: conversationID, marksActivity: false)
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
            return outputForConversationState(conversationID: conversationID, marksActivity: true)
        default:
            return []
        }
    }

    private func outputForConversationState(
        conversationID: String,
        marksActivity: Bool
    ) -> [CodexDesktopReducerOutput] {
        guard let state = conversationStates[conversationID]?.objectValue else {
            return []
        }

        return [
            .threadContextUpsert(
                threadContext(conversationID: conversationID, state: state),
                marksActivity: marksActivity
            ),
        ]
    }

    private func threadContext(
        conversationID: String,
        state: [String: JSONValue]
    ) -> CodexThreadContext {
        CodexThreadContext(
            threadID: conversationID,
            title: conversationTitle(from: state),
            activityLabel: conversationActivityLabel(from: state),
            phase: conversationPhase(from: state),
            inputTokenCount: state.integerValue(at: ["latestTokenUsageInfo", "total", "inputTokens"]),
            outputTokenCount: state.integerValue(at: ["latestTokenUsageInfo", "total", "outputTokens"])
        )
    }

    private func conversationTitle(from state: [String: JSONValue]) -> String? {
        firstString(in: state, paths: Self.titlePaths, normalize: normalizedThreadTitle)
    }

    private mutating func handleThreadMetadataUpdate(
        params: [String: JSONValue]
    ) -> [CodexDesktopReducerOutput] {
        guard let conversationID = conversationID(from: params),
              let title = metadataTitle(from: params)
        else {
            return []
        }

        var state = conversationStates[conversationID]?.objectValue ?? [:]
        state["id"] = state["id"] ?? .string(conversationID)
        state["title"] = .string(title)
        conversationStates[conversationID] = .object(state)
        return outputForConversationState(conversationID: conversationID, marksActivity: false)
    }

    private func conversationID(from params: [String: JSONValue]) -> String? {
        firstString(in: params, paths: Self.conversationIDPaths, normalize: normalizedIdentifier)
    }

    private func metadataTitle(from params: [String: JSONValue]) -> String? {
        conversationTitle(from: params)
    }

    private func firstString(
        in object: [String: JSONValue],
        paths: [[String]],
        normalize: (String?) -> String?
    ) -> String? {
        for path in paths {
            if let value = normalize(object.stringValue(at: path)) {
                return value
            }
        }

        return nil
    }

    private func normalizedIdentifier(_ rawIdentifier: String?) -> String? {
        guard let identifier = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              identifier.isEmpty == false
        else {
            return nil
        }

        return identifier
    }

    private func normalizedThreadTitle(_ rawTitle: String?) -> String? {
        guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false,
              looksLikeUUID(title) == false
        else {
            return nil
        }

        return title
    }

    private func looksLikeUUID(_ value: String) -> Bool {
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func conversationActivityLabel(from state: [String: JSONValue]) -> String {
        switch conversationPhase(from: state) {
        case .plan:
            return "Plan"
        case .working:
            return "Working"
        case .completed:
            return "Completed"
        case .connected:
            return "Connected"
        case .interrupted:
            return "Interrupted"
        case .error:
            return "Error"
        case .unknown:
            return "Connected"
        }
    }

    private func conversationPhase(from state: [String: JSONValue]) -> CodexThreadPhase {
        if let explicitMode = explicitMode(from: state) {
            return phaseForMode(explicitMode)
        }

        if let status = latestTurnStatus(from: state) {
            return phaseForStatus(status)
        }

        if let runtimeStatus = state.stringValue(at: ["threadRuntimeStatus", "type"]) {
            return phaseForStatus(runtimeStatus)
        }

        return .connected
    }

    private func explicitMode(from state: [String: JSONValue]) -> String? {
        let candidatePaths: [[String]] = [
            ["mode"],
            ["threadMode"],
            ["threadMode", "type"],
            ["thread", "mode"],
            ["thread", "mode", "type"],
            ["threadRuntimeStatus", "mode"],
        ]

        for path in candidatePaths {
            if let value = state.stringValue(at: path)?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }

        guard let turns = state.arrayValue(at: ["turns"]) else {
            return nil
        }

        return turns
            .compactMap(\.objectValue)
            .last?
            .stringValue(at: ["mode"])
    }

    private func latestTurnStatus(from state: [String: JSONValue]) -> String? {
        state.arrayValue(at: ["turns"])?
            .compactMap(\.objectValue)
            .last?
            .stringValue(at: ["status"])
    }

    private func phaseForMode(_ raw: String) -> CodexThreadPhase {
        let normalized = raw.lowercased()

        if normalized.contains("plan") {
            return .plan
        }

        return phaseForStatus(normalized)
    }

    private func phaseForStatus(_ raw: String) -> CodexThreadPhase {
        switch raw.lowercased() {
        case "planning", "plan":
            return .plan
        case "loading", "running", "streaming", "inprogress", "in_progress", "working":
            return .working
        case "completed", "done":
            return .completed
        case "idle", "loaded", "notloaded", "not_loaded", "connected":
            return .connected
        case "interrupted", "cancelled", "canceled":
            return .interrupted
        case "errored", "error", "failed":
            return .error
        default:
            return .unknown
        }
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

            guard index >= 0 else {
                return false
            }

            if remainingPath.isEmpty {
                switch operation {
                case "add":
                    if index <= array.count {
                        array.insert(value ?? .null, at: index)
                    } else {
                        return false
                    }
                case "replace":
                    guard index < array.count else {
                        return false
                    }
                    array[index] = value ?? .null
                case "remove":
                    guard index < array.count else {
                        return false
                    }
                    array.remove(at: index)
                default:
                    return false
                }
                node = .array(array)
                return true
            }

            guard index < array.count else {
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

    private func emptyContainer(for next: ConversationPatchPathComponent?) -> JSONValue {
        switch next {
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

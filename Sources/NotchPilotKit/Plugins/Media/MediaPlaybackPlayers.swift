import Foundation

enum MediaPlaybackPlayerID: Hashable, Sendable {
    case spotify
    case system
}

enum MediaPlaybackCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(TimeInterval)
}

protocol MediaPlaybackCommandPerforming: AnyObject {
    @discardableResult
    func perform(_ command: MediaPlaybackCommand) -> Bool
}

struct MediaPlaybackPlayerCommandRouter {
    private let commandPerformers: [MediaPlaybackPlayerID: any MediaPlaybackCommandPerforming]
    private let fallbackPlayer: MediaPlaybackPlayerID

    init(
        commandPerformers: [MediaPlaybackPlayerID: any MediaPlaybackCommandPerforming],
        fallbackPlayer: MediaPlaybackPlayerID
    ) {
        self.commandPerformers = commandPerformers
        self.fallbackPlayer = fallbackPlayer
    }

    @discardableResult
    func perform(
        _ command: MediaPlaybackCommand,
        selectedPlayer: MediaPlaybackPlayerID?
    ) -> MediaPlaybackPlayerID? {
        if let selectedPlayer,
           commandPerformers[selectedPlayer]?.perform(command) == true {
            return selectedPlayer
        }

        if selectedPlayer != fallbackPlayer,
           commandPerformers[fallbackPlayer]?.perform(command) == true {
            return fallbackPlayer
        }

        return nil
    }
}

struct MediaPlaybackPlayerSelector {
    private let players: [MediaPlaybackPlayerID]
    private var states: [MediaPlaybackPlayerID: MediaPlaybackState] = [:]
    private var selectedPlayer: MediaPlaybackPlayerID?

    var currentPlayer: MediaPlaybackPlayerID? {
        selectedPlayer
    }

    init(players: [MediaPlaybackPlayerID]) {
        self.players = players
    }

    mutating func update(
        _ state: MediaPlaybackState,
        for player: MediaPlaybackPlayerID,
        at date: Date = Date()
    ) -> MediaPlaybackState {
        states[player] = Self.projected(state, at: date)
        return selectedState(at: date)
    }

    mutating func reset() {
        states.removeAll()
        selectedPlayer = nil
    }

    func snapshot(for player: MediaPlaybackPlayerID, at date: Date = Date()) -> MediaPlaybackSnapshot? {
        guard let state = states[player] else {
            return nil
        }
        return Self.snapshot(from: Self.projected(state, at: date))
    }

    private mutating func selectedState(at date: Date) -> MediaPlaybackState {
        let projectedStates = states.mapValues { Self.projected($0, at: date) }

        if let selectedPlayer,
           let currentSnapshot = Self.snapshot(from: projectedStates[selectedPlayer]),
           currentSnapshot.isPlaying {
            return .active(currentSnapshot)
        }

        if let player = players.first(where: {
            Self.snapshot(from: projectedStates[$0])?.isPlaying == true
        }),
           let snapshot = Self.snapshot(from: projectedStates[player]) {
            selectedPlayer = player
            return .active(snapshot)
        }

        if let player = players.first(where: {
            Self.snapshot(from: projectedStates[$0]) != nil
        }),
           let snapshot = Self.snapshot(from: projectedStates[player]) {
            selectedPlayer = player
            return .active(snapshot)
        }

        selectedPlayer = nil

        if projectedStates.values.contains(.unavailable) {
            return .unavailable
        }

        return .idle
    }

    private static func snapshot(from state: MediaPlaybackState?) -> MediaPlaybackSnapshot? {
        guard case let .active(snapshot) = state else {
            return nil
        }
        return snapshot
    }

    private static func projected(_ state: MediaPlaybackState, at date: Date) -> MediaPlaybackState {
        guard case let .active(snapshot) = state else {
            return state
        }
        return .active(snapshot.replacingCurrentTime(snapshot.estimatedCurrentTime(at: date), at: date))
    }
}

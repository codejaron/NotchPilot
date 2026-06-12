import Foundation

struct MediaPlaybackTimeResolver {
    private struct TrackKey: Equatable {
        let source: MediaPlaybackSource
        let title: String
        let artist: String
        let album: String

        init(snapshot: MediaPlaybackSnapshot) {
            self.source = snapshot.source
            self.title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            self.album = snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct Anchor {
        let key: TrackKey
        let time: TimeInterval
        let date: Date
        let playbackRate: Double
        let duration: TimeInterval?

        func matches(_ snapshot: MediaPlaybackSnapshot, at date: Date, validity: TimeInterval) -> Bool {
            let elapsed = date.timeIntervalSince(self.date)
            return key == TrackKey(snapshot: snapshot) && elapsed >= 0 && elapsed <= validity
        }

        func projectedTime(at date: Date) -> TimeInterval {
            let elapsed = max(0, date.timeIntervalSince(self.date))
            let projected = time + elapsed * max(0, playbackRate)
            guard let duration else {
                return max(0, projected)
            }
            return min(max(0, projected), max(0, duration))
        }
    }

    private let anchorValidity: TimeInterval
    private var anchor: Anchor?

    init(anchorValidity: TimeInterval = 12) {
        self.anchorValidity = anchorValidity
    }

    mutating func resolve(_ state: MediaPlaybackState, receivedAt date: Date = Date()) -> MediaPlaybackState {
        guard case let .active(snapshot) = state else {
            anchor = nil
            return state
        }

        let anchorDate = max(snapshot.lastUpdated, date)
        let projectedTime = anchor.flatMap { existing -> TimeInterval? in
            guard existing.matches(snapshot, at: anchorDate, validity: anchorValidity) else {
                return nil
            }
            return existing.projectedTime(at: anchorDate)
        }

        if let projectedTime,
           snapshot.currentTime <= 0.25,
           projectedTime > 2 {
            let resolvedSnapshot = snapshot.replacingCurrentTime(projectedTime, at: anchorDate)
            remember(resolvedSnapshot)
            return .active(resolvedSnapshot)
        }

        remember(snapshot)
        return .active(snapshot)
    }

    mutating func reset() {
        anchor = nil
    }

    private mutating func remember(_ snapshot: MediaPlaybackSnapshot) {
        anchor = Anchor(
            key: TrackKey(snapshot: snapshot),
            time: snapshot.currentTime,
            date: snapshot.lastUpdated,
            playbackRate: snapshot.playbackRate,
            duration: snapshot.duration
        )
    }
}

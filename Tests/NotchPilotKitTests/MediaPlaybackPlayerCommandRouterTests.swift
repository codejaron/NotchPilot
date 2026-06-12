import XCTest
@testable import NotchPilotKit

final class MediaPlaybackPlayerCommandRouterTests: XCTestCase {
    func testRoutesCommandToSelectedSpotifyPlayer() {
        let spotify = RecordingCommandPerformer(result: true)
        let system = RecordingCommandPerformer(result: true)
        let router = MediaPlaybackPlayerCommandRouter(
            commandPerformers: [
                .spotify: spotify,
                .system: system,
            ],
            fallbackPlayer: .system
        )

        let player = router.perform(.nextTrack, selectedPlayer: .spotify)

        XCTAssertEqual(player, .spotify)
        XCTAssertEqual(spotify.commands, [.nextTrack])
        XCTAssertEqual(system.commands, [])
    }

    func testFallsBackToSystemWhenSelectedPlayerCannotRunCommand() {
        let spotify = RecordingCommandPerformer(result: false)
        let system = RecordingCommandPerformer(result: true)
        let router = MediaPlaybackPlayerCommandRouter(
            commandPerformers: [
                .spotify: spotify,
                .system: system,
            ],
            fallbackPlayer: .system
        )

        let player = router.perform(.pause, selectedPlayer: .spotify)

        XCTAssertEqual(player, .system)
        XCTAssertEqual(spotify.commands, [.pause])
        XCTAssertEqual(system.commands, [.pause])
    }

    func testUsesSystemWhenNoPlayerIsSelected() {
        let spotify = RecordingCommandPerformer(result: true)
        let system = RecordingCommandPerformer(result: true)
        let router = MediaPlaybackPlayerCommandRouter(
            commandPerformers: [
                .spotify: spotify,
                .system: system,
            ],
            fallbackPlayer: .system
        )

        let player = router.perform(.seek(12.5), selectedPlayer: nil)

        XCTAssertEqual(player, .system)
        XCTAssertEqual(spotify.commands, [])
        XCTAssertEqual(system.commands, [.seek(12.5)])
    }
}

private final class RecordingCommandPerformer: MediaPlaybackCommandPerforming {
    private let result: Bool
    private(set) var commands: [MediaPlaybackCommand] = []

    init(result: Bool) {
        self.result = result
    }

    func perform(_ command: MediaPlaybackCommand) -> Bool {
        commands.append(command)
        return result
    }
}

import Foundation

public enum PresentationTarget: Equatable, Sendable {
    case activeScreen
    case primaryScreen
    case screen(id: String)
    case allScreens
}

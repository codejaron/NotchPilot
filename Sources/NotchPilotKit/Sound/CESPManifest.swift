import Foundation

/// Decoded `openpeon.json` manifest, per CESP v1.0 Section 2.
///
/// Only the fields the player needs are strictly typed; everything else is
/// optional so forward-compatible pack manifests still decode cleanly.
public struct CESPManifest: Codable, Sendable, Equatable {
    public let cespVersion: String
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String?
    public let author: Author?
    public let license: String?
    public let language: String?
    public let homepage: String?
    public let categories: [String: CategoryEntry]
    public let icon: String?
    public let tags: [String]?

    public struct Author: Codable, Sendable, Equatable {
        public let name: String
        public let github: String?
    }

    public struct CategoryEntry: Codable, Sendable, Equatable {
        public let sounds: [Sound]
        public let icon: String?
    }

    public struct Sound: Codable, Sendable, Equatable {
        public let file: String
        public let label: String
        public let sha256: String?
        public let icon: String?
    }

    enum CodingKeys: String, CodingKey {
        case cespVersion = "cesp_version"
        case name
        case displayName = "display_name"
        case version
        case description
        case author
        case license
        case language
        case homepage
        case categories
        case icon
        case tags
    }
}

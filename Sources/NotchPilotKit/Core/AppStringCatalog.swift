import Foundation

struct AppStringCatalog: Sendable {
    static let shared = AppStringCatalog()

    private struct Catalog: Decodable {
        let strings: [String: CatalogEntry]
    }

    private struct CatalogEntry: Decodable {
        let localizations: [String: CatalogLocalization]?
    }

    private struct CatalogLocalization: Decodable {
        let stringUnit: CatalogStringUnit?
    }

    private struct CatalogStringUnit: Decodable {
        let value: String
    }

    private let strings: [String: [String: String]]

    init(bundle: Bundle = .module) {
        var strings = Self.xcstrings(from: bundle)

        for language in AppLanguage.allCases {
            for (key, value) in Self.compiledStrings(from: bundle, language: language) {
                strings[key, default: [:]][language.rawValue] = value
            }
        }

        self.strings = strings
    }

    func text(for key: AppTextKey, language: AppLanguage) -> String? {
        strings[key.rawValue]?[language.rawValue]
    }

    func hasTranslation(for key: AppTextKey, language: AppLanguage) -> Bool {
        text(for: key, language: language)?.isEmpty == false
    }

    private static func xcstrings(from bundle: Bundle) -> [String: [String: String]] {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else {
            return [:]
        }

        return catalog.strings.mapValues { entry in
            entry.localizations?.compactMapValues(\.stringUnit?.value) ?? [:]
        }
    }

    private static func compiledStrings(from bundle: Bundle, language: AppLanguage) -> [String: String] {
        guard let url = bundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language.rawValue
        ),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String]
        else {
            return [:]
        }

        return dictionary
    }
}

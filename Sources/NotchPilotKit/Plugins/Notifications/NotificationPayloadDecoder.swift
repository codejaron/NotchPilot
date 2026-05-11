import Foundation

public struct NotificationPayloadDecoder: Sendable {
    public struct DecodedPayload: Equatable, Sendable {
        public let bundleIdentifier: String
        public let title: String?
        public let subtitle: String?
        public let body: String?

        public init(bundleIdentifier: String, title: String? = nil, subtitle: String? = nil, body: String? = nil) {
            self.bundleIdentifier = bundleIdentifier
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }
    }

    public init() {}

    public func decode(payload: Data) -> DecodedPayload? {
        guard !payload.isEmpty else { return nil }

        // Try NSKeyedUnarchiver first (modern, archiver-wrapped shape).
        if let archived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSArray.self, NSData.self, NSDate.self],
            from: payload
        ) as? [String: Any], let result = extractFields(from: archived) {
            return result
        }

        // Fallback: plain property-list dict (no archiver wrapping).
        if let plist = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil) as? [String: Any],
           let result = extractFields(from: plist) {
            return result
        }

        return nil
    }

    private func extractFields(from dict: [String: Any]) -> DecodedPayload? {
        let bundleID = (dict["app"] as? String)
            ?? (dict["appBundleIdentifier"] as? String)

        guard let bundle = bundleID else {
            return nil
        }

        let request = (dict["req"] as? [String: Any])
            ?? (dict["request"] as? [String: Any])
            ?? dict   // Some payloads put fields at the root.

        let title = (request["titl"] as? String)
            ?? (request["title"] as? String)
        let subtitle = (request["subt"] as? String)
            ?? (request["subtitle"] as? String)
        let body = (request["body"] as? String)
            ?? (request["informativeText"] as? String)

        return DecodedPayload(
            bundleIdentifier: bundle,
            title: title,
            subtitle: subtitle,
            body: body
        )
    }
}

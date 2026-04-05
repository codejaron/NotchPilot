import Foundation

public enum JSONValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(jsonObject: Any) throws {
        switch jsonObject {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .integer(value)
        case let value as Double:
            self = .double(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if NSNumber(value: value.intValue) == value {
                self = .integer(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as [String: Any]:
            self = .object(try value.mapValues(JSONValue.init(jsonObject:)))
        case let value as [Any]:
            self = .array(try value.map(JSONValue.init(jsonObject:)))
        case _ as NSNull:
            self = .null
        default:
            throw JSONValueError.unsupportedType
        }
    }

    var jsonObject: Any {
        switch self {
        case let .string(value):
            value
        case let .integer(value):
            value
        case let .double(value):
            value
        case let .bool(value):
            value
        case let .object(value):
            value.mapValues(\.jsonObject)
        case let .array(value):
            value.map(\.jsonObject)
        case .null:
            NSNull()
        }
    }

    var stringValue: String? {
        switch self {
        case let .string(value):
            value
        case let .integer(value):
            "\(value)"
        case let .double(value):
            "\(value)"
        default:
            nil
        }
    }

    var integerValue: Int? {
        switch self {
        case let .integer(value):
            value
        case let .double(value):
            Int(value)
        case let .string(value):
            Int(value)
        default:
            nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            value
        default:
            nil
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }
}

enum JSONValueError: Error {
    case unsupportedType
}

extension Dictionary where Key == String, Value == JSONValue {
    func jsonValue(at path: [String]) -> JSONValue? {
        guard let first = path.first else {
            return nil
        }

        let value = self[first]
        guard path.count > 1 else {
            return value
        }

        return value?.objectValue?.jsonValue(at: Array(path.dropFirst()))
    }

    func stringValue(at path: [String]) -> String? {
        jsonValue(at: path)?.stringValue
    }

    func integerValue(at path: [String]) -> Int? {
        jsonValue(at: path)?.integerValue
    }

    func arrayValue(at path: [String]) -> [JSONValue]? {
        jsonValue(at: path)?.arrayValue
    }

    func objectValue(at path: [String]) -> [String: JSONValue]? {
        jsonValue(at: path)?.objectValue
    }
}

import Foundation

// MARK: - JSON-RPC Types

struct JsonRpcRequest: Codable {
    let jsonrpc: String
    let id: JsonRpcId?
    let method: String
    let params: [String: AnyCodable]?

    init(method: String, params: [String: Any]? = nil) {
        self.jsonrpc = "2.0"
        self.id = .string(UUID().uuidString)
        self.method = method
        self.params = params?.mapValues { AnyCodable($0) }
    }
}

struct JsonRpcResponse: Codable {
    let jsonrpc: String
    let id: JsonRpcId?
    let result: AnyCodable?
    let error: JsonRpcErrorObj?
}

struct JsonRpcErrorObj: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

struct JsonRpcNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodable]?
}

enum JsonRpcId: Codable, Equatable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.typeMismatch(JsonRpcId.self, .init(codingPath: [], debugDescription: "Expected string or number"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str): try container.encode(str)
        case .number(let num): try container.encode(num)
        }
    }
}

// MARK: - AnyCodable wrapper for dynamic JSON

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var arrayValue: [Any]? { value as? [Any] }
}

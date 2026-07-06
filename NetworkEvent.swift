import Foundation

public struct NetworkEvent: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started
        case completed
    }

    public struct NetworkTransportMessage: Codable, Sendable {
        public enum MessageType: String, Codable, Sendable {
            case event
            case clientHello
        }

        public let type: MessageType
        public let event: NetworkEvent?
        public let client: NetworkEvent.ClientInfo?

        public init(event: NetworkEvent) {
            self.type = .event
            self.event = event
            self.client = nil
        }

        public init(clientHello client: NetworkEvent.ClientInfo) {
            self.type = .clientHello
            self.event = nil
            self.client = client
        }
    }

    public struct RequestPayload: Codable, Sendable {
        public let url: String
        public let method: String
        public let headers: [String: String]
        public let body: String?

        public init(url: String, method: String, headers: [String: String], body: String?) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
        }
    }

    public struct ResponsePayload: Codable, Sendable {
        public let statusCode: Int?
        public let headers: [String: String]
        public let body: String?
        public let error: String?
        public let durationMS: Int

        public init(statusCode: Int?, headers: [String: String], body: String?, error: String?, durationMS: Int) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.error = error
            self.durationMS = durationMS
        }
    }

    public struct ClientInfo: Codable, Sendable {
        public let deviceName: String
        public let appName: String
        public let bundleIdentifier: String?

        public init(deviceName: String, appName: String, bundleIdentifier: String?) {
            self.deviceName = deviceName
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public let id: UUID
    public let kind: Kind
    public let timestamp: Date
    public let requestID: UUID
    public let request: RequestPayload
    public let response: ResponsePayload?
    public let client: ClientInfo?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        timestamp: Date = Date(),
        requestID: UUID,
        request: RequestPayload,
        response: ResponsePayload?,
        client: ClientInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.requestID = requestID
        self.request = request
        self.response = response
        self.client = client
    }
}

func stringDictionary(from headers: [AnyHashable: Any]?) -> [String: String] {
    guard let headers else { return [:] }
    return headers.reduce(into: [:]) { output, item in
        output[String(describing: item.key)] = String(describing: item.value)
    }
}

func decodeBody(_ data: Data?) -> String? {
    guard let data, !data.isEmpty else { return nil }
    if let utf8String = String(data: data, encoding: .utf8) {
        return utf8String
    }
    return data.base64EncodedString()
}

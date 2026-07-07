import Foundation

struct NetworkEvent: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case started
        case completed
    }

    struct NetworkTransportMessage: Codable, Sendable {
        enum MessageType: String, Codable, Sendable {
            case event
            case clientHello
        }

        let type: MessageType
        let event: NetworkEvent?
        let client: NetworkEvent.ClientInfo?

        init(event: NetworkEvent) {
            self.type = .event
            self.event = event
            self.client = nil
        }

        init(clientHello client: NetworkEvent.ClientInfo) {
            self.type = .clientHello
            self.event = nil
            self.client = client
        }
    }

    struct RequestPayload: Codable, Sendable {
        let url: String
        let method: String
        let headers: [String: String]
        let body: String?

        init(url: String, method: String, headers: [String: String], body: String?) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
        }
    }

    struct ResponsePayload: Codable, Sendable {
        let statusCode: Int?
        let headers: [String: String]
        let body: String?
        let error: String?
        let durationMS: Int

        init(statusCode: Int?, headers: [String: String], body: String?, error: String?, durationMS: Int) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.error = error
            self.durationMS = durationMS
        }
    }

    struct ClientInfo: Codable, Sendable {
        let deviceName: String
        let appName: String
        let bundleIdentifier: String?

        init(deviceName: String, appName: String, bundleIdentifier: String?) {
            self.deviceName = deviceName
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
        }
    }

    let id: UUID
    let kind: Kind
    let timestamp: Date
    let requestID: UUID
    let request: RequestPayload
    let response: ResponsePayload?
    let client: ClientInfo?

    init(
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

import Foundation

struct SocketCaptureEvent: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case created
        case resumed
        case message
        case ping
        case closed
        case cancelled
        case failed
    }

    enum Direction: String, Equatable, Sendable {
        case inbound
        case outbound
    }

    enum Payload: Equatable, Sendable {
        case text(String)
        case binary(Data)

        var byteCount: Int {
            switch self {
            case .text(let value):
                return value.lengthOfBytes(using: .utf8)
            case .binary(let value):
                return value.count
            }
        }
    }

    let id: UUID
    let connectionID: UUID
    let timestamp: Date
    let kind: Kind
    let direction: Direction?
    let endpoint: String
    let payload: Payload?
    let closeCode: Int?
    let closeReason: Data?
    let errorDescription: String?

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        timestamp: Date = Date(),
        kind: Kind,
        direction: Direction? = nil,
        endpoint: String,
        payload: Payload? = nil,
        closeCode: Int? = nil,
        closeReason: Data? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.timestamp = timestamp
        self.kind = kind
        self.direction = direction
        self.endpoint = endpoint
        self.payload = payload
        self.closeCode = closeCode
        self.closeReason = closeReason
        self.errorDescription = errorDescription
    }
}

#if DEBUG
extension SocketCaptureEvent {
    static func fixture(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        connectionID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        kind: Kind = .message,
        direction: Direction? = .outbound,
        endpoint: String = "ws://127.0.0.1:8089/echo",
        payload: Payload? = .text("hello"),
        closeCode: Int? = nil,
        closeReason: Data? = nil,
        errorDescription: String? = nil
    ) -> SocketCaptureEvent {
        SocketCaptureEvent(
            id: id,
            connectionID: connectionID,
            timestamp: timestamp,
            kind: kind,
            direction: direction,
            endpoint: endpoint,
            payload: payload,
            closeCode: closeCode,
            closeReason: closeReason,
            errorDescription: errorDescription
        )
    }
}
#endif

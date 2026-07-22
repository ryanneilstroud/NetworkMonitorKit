import Foundation

struct SocketTransportEvent: Codable, Equatable, Sendable {
    enum PayloadKind: String, Codable, Sendable {
        case text
        case binary
    }

    let id: UUID
    let connectionID: UUID
    let timestamp: Date
    let kind: SocketCaptureEvent.Kind
    let direction: SocketCaptureEvent.Direction?
    let endpoint: String
    let payloadKind: PayloadKind?
    let payload: String?
    let payloadByteCount: Int?
    let payloadWasTruncated: Bool
    let closeCode: Int?
    let closeReason: String?
    let errorDescription: String?

    init(captureEvent event: SocketCaptureEvent, maximumPayloadBytes: Int) {
        id = event.id
        connectionID = event.connectionID
        timestamp = event.timestamp
        kind = event.kind
        direction = event.direction
        endpoint = event.endpoint
        closeCode = event.closeCode
        closeReason = event.closeReason.map { String(decoding: $0, as: UTF8.self) }
        errorDescription = event.errorDescription

        let byteLimit = max(0, maximumPayloadBytes)
        switch event.payload {
        case .text(let text):
            let bytes = Data(text.utf8)
            payloadKind = .text
            payloadByteCount = bytes.count
            payloadWasTruncated = bytes.count > byteLimit
            payload = Self.boundedUTF8String(bytes, byteLimit: byteLimit)
        case .binary(let data):
            payloadKind = .binary
            payloadByteCount = data.count
            payloadWasTruncated = data.count > byteLimit
            payload = Data(data.prefix(byteLimit)).base64EncodedString()
        case nil:
            payloadKind = nil
            payload = nil
            payloadByteCount = nil
            payloadWasTruncated = false
        }
    }

    private static func boundedUTF8String(_ data: Data, byteLimit: Int) -> String {
        var prefix = Data(data.prefix(byteLimit))
        while !prefix.isEmpty {
            if let value = String(data: prefix, encoding: .utf8) {
                return value
            }
            prefix.removeLast()
        }
        return ""
    }
}

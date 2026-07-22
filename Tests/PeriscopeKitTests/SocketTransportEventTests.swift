import Foundation
import Testing
@testable import PeriscopeKit

@Suite("WebSocket transport mapping")
struct SocketTransportEventTests {
    @Test("preserves text metadata and truncates by UTF-8 bytes")
    func mapsTruncatedText() throws {
        // Given
        let captureEvent = SocketCaptureEvent.fixture(payload: .text("hello world"))

        // When
        let event = SocketTransportEvent(captureEvent: captureEvent, maximumPayloadBytes: 5)

        // Then
        #expect(event.payloadKind == .text)
        #expect(event.payload == "hello")
        #expect(event.payloadByteCount == 11)
        #expect(event.payloadWasTruncated)
    }

    @Test("does not split a UTF-8 scalar at the payload boundary")
    func preservesValidUTF8WhenTruncating() {
        // Given
        let captureEvent = SocketCaptureEvent.fixture(payload: .text("a😀b"))

        // When
        let event = SocketTransportEvent(captureEvent: captureEvent, maximumPayloadBytes: 3)

        // Then
        #expect(event.payload == "a")
        #expect(event.payloadByteCount == 6)
        #expect(event.payloadWasTruncated)
    }

    @Test("encodes bounded binary payload as base64")
    func mapsTruncatedBinary() throws {
        // Given
        let captureEvent = SocketCaptureEvent.fixture(payload: .binary(Data([0, 1, 2, 3])))

        // When
        let event = SocketTransportEvent(captureEvent: captureEvent, maximumPayloadBytes: 3)

        // Then
        #expect(event.payloadKind == .binary)
        #expect(event.payload == Data([0, 1, 2]).base64EncodedString())
        #expect(event.payloadByteCount == 4)
        #expect(event.payloadWasTruncated)
    }

    @Test("recorder forwards the mapped transport event")
    func recorderForwardsMappedEvent() throws {
        // Given
        let spy = SocketTransportEventSpy()
        let recorder = TransportSocketEventRecorder(maximumPayloadBytes: 64) { event in
            spy.record(event)
        }
        let captureEvent = SocketCaptureEvent.fixture(payload: .text("hello"))

        // When
        recorder.record(captureEvent)

        // Then
        let event = try #require(spy.events.first)
        #expect(event.id == captureEvent.id)
        #expect(event.connectionID == captureEvent.connectionID)
        #expect(event.payload == "hello")
    }

    @Test("encodes an additive socketEvent envelope")
    func encodesTransportEnvelope() throws {
        // Given
        let socketEvent = SocketTransportEvent(
            captureEvent: .fixture(payload: .text("hello")),
            maximumPayloadBytes: 64
        )
        let message = NetworkEvent.NetworkTransportMessage(socketEvent: socketEvent)

        // When
        let data = try JSONEncoder().encode(message)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Then
        #expect(object["type"] as? String == "socketEvent")
        let encodedEvent = try #require(object["socketEvent"] as? [String: Any])
        #expect(encodedEvent["payload"] as? String == "hello")
        #expect(object["event"] == nil)
    }
}

private final class SocketTransportEventSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [SocketTransportEvent] = []

    var events: [SocketTransportEvent] {
        lock.withLock { recordedEvents }
    }

    func record(_ event: SocketTransportEvent) {
        lock.withLock { recordedEvents.append(event) }
    }
}

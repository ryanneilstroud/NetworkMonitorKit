import Foundation
import Testing
@testable import PeriscopeKit

@Suite("WebSocket capture coordinator", .serialized)
struct WebSocketCaptureCoordinatorTests {
    @Test("records message direction, payload, endpoint, and stable connection identity")
    func recordsMessages() throws {
        // Given
        let recorder = SocketEventRecorderSpy()
        let coordinator = WebSocketCaptureCoordinator()
        coordinator.enable(recorder: recorder)
        defer { coordinator.disable() }
        let endpoint = try #require(URL(string: "ws://127.0.0.1:8089/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)

        // When
        coordinator.recordOutgoing(.string("hello"), for: task)
        coordinator.recordIncoming(.data(Data([0x01, 0x02])), for: task)

        // Then
        let events = recorder.events
        #expect(events.count == 3)
        #expect(events[0].kind == .created)
        #expect(events[1].kind == .message)
        #expect(events[1].direction == .outbound)
        #expect(events[1].payload == .text("hello"))
        #expect(events[2].direction == .inbound)
        #expect(events[2].payload == .binary(Data([0x01, 0x02])))
        #expect(Set(events.map(\.connectionID)).count == 1)
        #expect(events.allSatisfy { $0.endpoint == endpoint.absoluteString })
    }

    @Test("records resume once while preserving repeated lifecycle events")
    func deduplicatesResume() throws {
        // Given
        let recorder = SocketEventRecorderSpy()
        let coordinator = WebSocketCaptureCoordinator()
        coordinator.enable(recorder: recorder)
        defer { coordinator.disable() }
        let endpoint = try #require(URL(string: "ws://127.0.0.1:8089/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)

        // When
        coordinator.recordResume(for: task)
        coordinator.recordResume(for: task)
        coordinator.recordPing(for: task)
        coordinator.recordPing(for: task)

        // Then
        #expect(recorder.events.map(\.kind) == [.resumed, .ping, .ping])
    }

    @Test("does not record while disabled")
    func disabledRecorderIsTransparent() throws {
        // Given
        let recorder = SocketEventRecorderSpy()
        let coordinator = WebSocketCaptureCoordinator()
        let endpoint = try #require(URL(string: "ws://127.0.0.1:8089/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)

        // When
        coordinator.enable(recorder: recorder)
        coordinator.disable()
        coordinator.recordOutgoing(.string("ignored"), for: task)

        // Then
        #expect(recorder.events.isEmpty)
    }
}

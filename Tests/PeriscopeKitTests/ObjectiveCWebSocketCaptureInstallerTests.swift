import Foundation
import Testing
@testable import PeriscopeKit

@Suite("Automatic native WebSocket capture", .serialized)
struct ObjectiveCWebSocketCaptureInstallerTests {
    @Test("installation is idempotent and captures callback-based outgoing messages")
    func capturesCallbackSend() async throws {
        // Given
        let installer = ObjectiveCWebSocketCaptureInstaller.shared
        #expect(installer.install() == .available)
        #expect(installer.install() == .available)
        let recorder = SocketEventRecorderSpy()
        WebSocketCaptureCoordinator.shared.disable()
        WebSocketCaptureCoordinator.shared.enable(recorder: recorder)
        defer { WebSocketCaptureCoordinator.shared.disable() }
        let endpoint = try #require(URL(string: "ws://127.0.0.1:9/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)

        // When
        task.send(.string("callback-message")) { _ in }
        await Task.yield()

        // Then
        let messages = recorder.events.filter { $0.kind == .message }
        #expect(messages.count == 1)
        #expect(messages.first?.direction == .outbound)
        #expect(messages.first?.payload == .text("callback-message"))
        task.cancel()
    }

    @Test("captures async outgoing and incoming messages through Objective-C selectors", .timeLimit(.minutes(1)))
    func capturesAsyncRoundTrip() async throws {
        // Given
        let server = LocalWebSocketServerFake()
        try await server.start(port: 18_089)
        defer { server.stop() }
        let installer = ObjectiveCWebSocketCaptureInstaller.shared
        #expect(installer.install() == .available)
        let recorder = SocketEventRecorderSpy()
        WebSocketCaptureCoordinator.shared.disable()
        WebSocketCaptureCoordinator.shared.enable(recorder: recorder)
        defer { WebSocketCaptureCoordinator.shared.disable() }
        let endpoint = try #require(URL(string: "ws://127.0.0.1:18089/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)
        task.resume()

        // When
        try await task.send(.data(Data([0xCA, 0xFE])))
        let reply = try await task.receive()

        // Then
        let messages = recorder.events.filter { $0.kind == .message }
        if case .data(let data) = reply {
            #expect(data == Data([0xCA, 0xFE]))
        } else {
            Issue.record("Expected a binary WebSocket reply")
        }
        #expect(messages.count == 2)
        #expect(messages.map(\.direction) == [.outbound, .inbound])
        #expect(messages.allSatisfy { $0.payload == .binary(Data([0xCA, 0xFE])) })
        task.cancel(with: .normalClosure, reason: nil)
    }

    @Test("captures callback outgoing and incoming messages without changing callbacks", .timeLimit(.minutes(1)))
    func capturesCallbackRoundTrip() async throws {
        // Given
        let server = LocalWebSocketServerFake()
        try await server.start(port: 18_090)
        defer { server.stop() }
        #expect(ObjectiveCWebSocketCaptureInstaller.shared.install() == .available)
        let recorder = SocketEventRecorderSpy()
        WebSocketCaptureCoordinator.shared.disable()
        WebSocketCaptureCoordinator.shared.enable(recorder: recorder)
        defer { WebSocketCaptureCoordinator.shared.disable() }
        let endpoint = try #require(URL(string: "ws://127.0.0.1:18090/echo"))
        let task = URLSession.shared.webSocketTask(with: endpoint)
        task.resume()

        // When
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(.string("callback-round-trip")) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>) in
            task.receive { result in
                continuation.resume(with: result)
            }
        }

        // Then
        let messages = recorder.events.filter { $0.kind == .message }
        if case .string(let text) = reply {
            #expect(text == "callback-round-trip")
        } else {
            Issue.record("Expected a text WebSocket reply")
        }
        #expect(messages.count == 2)
        #expect(messages.map(\.direction) == [.outbound, .inbound])
        #expect(messages.allSatisfy { $0.payload == .text("callback-round-trip") })
        task.cancel(with: .normalClosure, reason: nil)
    }
}

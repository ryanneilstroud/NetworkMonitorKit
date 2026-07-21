import Foundation
import Network

final class LocalWebSocketServerFake: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PeriscopeKitTests.LocalWebSocketServerFake")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lock = NSLock()

    func start(port: UInt16) async throws {
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        let parameters = NWParameters(tls: nil)
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        try await withCheckedThrowingContinuation { continuation in
            let continuationState = ContinuationState(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuationState.resume()
                case .failed(let error):
                    continuationState.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let active = lock.withLock {
            let result = connections
            connections.removeAll()
            return result
        }
        active.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection)
            case .failed, .cancelled:
                self.remove(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            guard let self, let connection else { return }
            if error != nil {
                self.remove(connection)
                return
            }
            if let data,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .text || metadata.opcode == .binary {
                let responseMetadata = NWProtocolWebSocket.Metadata(opcode: metadata.opcode)
                let responseContext = NWConnection.ContentContext(
                    identifier: "periscope-kit-tests.echo",
                    metadata: [responseMetadata]
                )
                connection.send(
                    content: data,
                    contentContext: responseContext,
                    isComplete: true,
                    completion: .idempotent
                )
            }
            self.receive(on: connection)
        }
    }

    private func remove(_ connection: NWConnection) {
        lock.withLock {
            connections.removeAll { $0 === connection }
        }
    }
}

private final class ContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

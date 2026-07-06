import Foundation
import Network

actor EventTransport {
    static let shared = EventTransport()

    private var connection: NWConnection?
    private var isReady = false

    func configure(host: String, port: UInt16) {
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 61337)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                switch state {
                case .ready:
                    await self.setReady(true)
                case .cancelled, .failed:
                    await self.setReady(false)
                default:
                    break
                }
            }
        }
        connection.start(queue: .global())
        self.connection = connection
    }

    func send(_ event: NetworkEvent) async {
        guard isReady, let connection else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(event)
            line.append(0x0A)
            connection.send(content: line, completion: .contentProcessed({ _ in }))
        } catch {
            // Intentionally dropped: monitoring should not crash user apps.
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        isReady = false
    }

    private func setReady(_ value: Bool) {
        isReady = value
    }
}


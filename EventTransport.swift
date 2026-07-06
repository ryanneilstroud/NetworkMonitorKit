import Foundation
import Network

actor EventTransport {
    static let shared = EventTransport()

    private var connection: NWConnection?
    private var isReady = false
    private var host: String?
    private var port: UInt16?
    private var pendingEvents: [NetworkEvent] = []
    private let maxPendingEvents = 500

    func configure(host: String, port: UInt16) {
        self.host = host
        self.port = port
        connectIfNeeded(forceNew: true)
    }

    func send(_ event: NetworkEvent) async {
        if !isReady || connection == nil {
            enqueue(event)
            connectIfNeeded(forceNew: false)
            return
        }
        guard let connection else { return }
        send(event, over: connection)
    }

    func stop() {
        connection?.cancel()
        connection = nil
        isReady = false
    }

    private func connectIfNeeded(forceNew: Bool) {
        guard let host, let port else { return }
        if !forceNew, connection != nil { return }

        connection?.cancel()
        isReady = false

        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 61337)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task {
                switch state {
                case .ready:
                    await self.setReady(true, for: connection)
                case .cancelled, .failed:
                    await self.handleDisconnected(connection)
                default:
                    break
                }
            }
        }
        connection.start(queue: .global())
        self.connection = connection
    }

    private func setReady(_ value: Bool, for connection: NWConnection) {
        guard self.connection === connection else { return }
        isReady = value
        if value {
            flushPending(over: connection)
        }
    }

    private func handleDisconnected(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        self.connection = nil
        isReady = false
    }

    private func send(_ event: NetworkEvent, over connection: NWConnection) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(event)
            line.append(0x0A)
            connection.send(content: line, completion: .contentProcessed({ [weak self, weak connection] error in
                guard let self, let connection else { return }
                Task {
                    await self.handleSendCompletion(error: error, event: event, over: connection)
                }
            }))
        } catch {
            // Intentionally dropped: monitoring should not crash user apps.
        }
    }

    private func handleSendCompletion(error: NWError?, event: NetworkEvent, over connection: NWConnection) {
        guard let error else { return }
        _ = error
        guard self.connection === connection else { return }
        enqueue(event)
        connection.cancel()
        self.connection = nil
        isReady = false
        connectIfNeeded(forceNew: false)
    }

    private func enqueue(_ event: NetworkEvent) {
        pendingEvents.append(event)
        if pendingEvents.count > maxPendingEvents {
            pendingEvents.removeFirst(pendingEvents.count - maxPendingEvents)
        }
    }

    private func flushPending(over connection: NWConnection) {
        guard !pendingEvents.isEmpty else { return }
        let buffered = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        for event in buffered {
            send(event, over: connection)
        }
    }
}

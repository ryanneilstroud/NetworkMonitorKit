import Foundation
import Network
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

actor EventTransport {
    static let shared = EventTransport()

    private var connection: NWConnection?
    private var isReady = false
    private var host: String?
    private var port: UInt16?
    private var pendingEvents: [NetworkEvent] = []
    private let maxPendingEvents = 500
    private let clientInfo = EventTransport.makeClientInfo()
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
            sendClientHello(over: connection)
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
            let encoder = Self.makeJSONEncoder()
            let payload = NetworkEvent.NetworkTransportMessage(event: enriched(event))
            try send(payload: payload, over: connection, encoder: encoder, trackedEvent: event)
        } catch {
            // Intentionally dropped: monitoring should not crash user apps.
        }
    }

    private func sendClientHello(over connection: NWConnection) {
        do {
            let encoder = Self.makeJSONEncoder()
            let payload = NetworkEvent.NetworkTransportMessage(clientHello: clientInfo)
            try send(payload: payload, over: connection, encoder: encoder, trackedEvent: nil)
        } catch {
            // Intentionally dropped: monitoring should not crash user apps.
        }
    }

    private func send(
        payload: NetworkEvent.NetworkTransportMessage,
        over connection: NWConnection,
        encoder: JSONEncoder,
        trackedEvent: NetworkEvent?
    ) throws {
        var line = try encoder.encode(payload)
        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self, let connection else { return }
            Task {
                await self.handleSendCompletion(error: error, event: trackedEvent, over: connection)
            }
        }))
    }

    private func handleSendCompletion(error: NWError?, event: NetworkEvent?, over connection: NWConnection) {
        guard error != nil else { return }
        guard self.connection === connection else { return }
        if let event {
            enqueue(event)
        }
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

    private func enriched(_ event: NetworkEvent) -> NetworkEvent {
        guard event.client == nil else { return event }
        return NetworkEvent(
            id: event.id,
            kind: event.kind,
            timestamp: event.timestamp,
            requestID: event.requestID,
            request: event.request,
            response: event.response,
            client: clientInfo
        )
    }

    private static func makeClientInfo() -> NetworkEvent.ClientInfo {
        let appName =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            ProcessInfo.processInfo.processName
        let bundleIdentifier = Bundle.main.bundleIdentifier

        #if canImport(UIKit)
        let deviceName: String
        if Thread.isMainThread {
            deviceName = UIDevice.current.name
        } else {
            deviceName = DispatchQueue.main.sync { UIDevice.current.name }
        }
        #elseif canImport(AppKit)
        let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        let deviceName = ProcessInfo.processInfo.hostName
        #endif

        return NetworkEvent.ClientInfo(
            deviceName: deviceName,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601Formatter.string(from: date))
        }
        return encoder
    }
}

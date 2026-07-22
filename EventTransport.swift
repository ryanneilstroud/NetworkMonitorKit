import Foundation
import Network
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

actor EventTransport {
    private enum PendingEvent: Sendable {
        case network(NetworkEvent)
        case socket(SocketTransportEvent)
    }

    static let shared = EventTransport()

    private var connection: NWConnection?
    private var isReady = false
    private var host: String?
    private var port: UInt16?
    private var pendingEvents: [PendingEvent] = []
    private let maxPendingEvents = 500
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var pathMonitor: NWPathMonitor?
    private var hasStartedPathMonitor = false
    private var isNetworkPathSatisfied = true
    private var hasObservedUnsatisfiedPath = false
    private let clientInfo = EventTransport.makeClientInfo()
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func configure(host: String, port: UInt16) {
        ensurePathMonitorStarted()
        self.host = host
        self.port = port
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        connectIfNeeded(forceNew: true)
    }

    func send(_ event: NetworkEvent) async {
        send(.network(event))
    }

    func send(_ event: SocketTransportEvent) async {
        send(.socket(event))
    }

    private func send(_ event: PendingEvent) {
        if !isReady || connection == nil {
            enqueue(event)
            connectIfNeeded(forceNew: false)
            scheduleReconnectIfNeeded()
            return
        }
        guard let connection else { return }
        send(event, over: connection)
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        connection?.cancel()
        connection = nil
        isReady = false
    }

    private func connectIfNeeded(forceNew: Bool) {
        guard let host, let port else { return }
        if !forceNew {
            if connection != nil { return }
            if reconnectTask != nil { return }
        }

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
                case .waiting:
                    await self.handleWaiting(connection)
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

    private func ensurePathMonitorStarted() {
        guard !hasStartedPathMonitor else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handlePathUpdate(path.status)
            }
        }
        monitor.start(queue: .global())
        pathMonitor = monitor
        hasStartedPathMonitor = true
    }

    private func setReady(_ value: Bool, for connection: NWConnection) {
        guard self.connection === connection else { return }
        isReady = value
        if value {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            sendClientHello(over: connection)
            flushPending(over: connection)
        }
    }

    private func handleWaiting(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        isReady = false
        scheduleReconnectIfNeeded()
    }

    private func handleDisconnected(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        self.connection = nil
        isReady = false
        scheduleReconnectIfNeeded()
    }

    private func send(_ event: PendingEvent, over connection: NWConnection) {
        do {
            let encoder = Self.makeJSONEncoder()
            let payload: NetworkEvent.NetworkTransportMessage
            switch event {
            case .network(let networkEvent):
                payload = NetworkEvent.NetworkTransportMessage(event: enriched(networkEvent))
            case .socket(let socketEvent):
                payload = NetworkEvent.NetworkTransportMessage(socketEvent: socketEvent)
            }
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
        trackedEvent: PendingEvent?
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

    private func handleSendCompletion(error: NWError?, event: PendingEvent?, over connection: NWConnection) {
        guard error != nil else { return }
        guard self.connection === connection else { return }
        if let event {
            enqueue(event)
        }
        connection.cancel()
        self.connection = nil
        isReady = false
        scheduleReconnect(forceNow: true)
    }

    private func enqueue(_ event: PendingEvent) {
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

    private func handlePathUpdate(_ status: NWPath.Status) {
        switch status {
        case .satisfied:
            isNetworkPathSatisfied = true
            guard host != nil, port != nil else { return }
            if hasObservedUnsatisfiedPath {
                hasObservedUnsatisfiedPath = false
                connection?.cancel()
                connection = nil
                isReady = false
                scheduleReconnect(forceNow: true)
                return
            }

            guard !isReady || connection == nil else { return }
            scheduleReconnect(forceNow: true)
        case .requiresConnection, .unsatisfied:
            isNetworkPathSatisfied = false
            hasObservedUnsatisfiedPath = true
            isReady = false
            connection?.cancel()
            connection = nil
            reconnectTask?.cancel()
            reconnectTask = nil
        @unknown default:
            break
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard host != nil, port != nil else { return }
        guard !isReady else { return }
        guard isNetworkPathSatisfied else { return }
        scheduleReconnect(forceNow: false)
    }

    private func scheduleReconnect(forceNow: Bool) {
        guard host != nil, port != nil else { return }

        if forceNow {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            connectIfNeeded(forceNew: true)
            return
        }

        guard reconnectTask == nil else { return }
        let delayNanoseconds = reconnectDelayNanoseconds(for: reconnectAttempt)
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await self?.performScheduledReconnect()
        }
    }

    private func performScheduledReconnect() {
        reconnectTask = nil
        guard !isReady else { return }
        connectIfNeeded(forceNew: true)
    }

    private func reconnectDelayNanoseconds(for attempt: Int) -> UInt64 {
        let exponent = min(attempt, 5)
        let delayMilliseconds = min(250 * (1 << exponent), 8_000)
        return UInt64(delayMilliseconds) * 1_000_000
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

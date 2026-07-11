import Foundation

public final class Periscope {
    public struct Receiver: Sendable, Hashable {
        let host: String
        let port: UInt16

        private init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }

        public static func device(host: String, port: Int = 61337) -> Receiver {
            precondition((1...65_535).contains(port), "Periscope receiver port must be between 1 and 65535.")
            return Receiver(host: host, port: UInt16(port))
        }

        public static func simulator(port: Int = 61337) -> Receiver {
            device(host: "localhost", port: port)
        }
    }

    public static let `default` = Periscope()
    private let stateLock = NSLock()
    private var isConfigured = false

    public init() {}

    public func capture(for receiver: Receiver) {
        stateLock.lock()
        let canConfigure = !isConfigured
        if canConfigure {
            isConfigured = true
        }
        stateLock.unlock()
        guard canConfigure else { return }

        URLProtocol.registerClass(MonitorURLProtocol.self)
        Task {
            await EventTransport.shared.configure(host: receiver.host, port: receiver.port)
        }
    }

    public func stop() {
        stateLock.lock()
        let wasConfigured = isConfigured
        isConfigured = false
        stateLock.unlock()
        guard wasConfigured else { return }

        URLProtocol.unregisterClass(MonitorURLProtocol.self)
        Task {
            await EventTransport.shared.stop()
        }
    }

    // Use this helper for explicit session setups where URLProtocol registration
    // doesn't get inherited automatically.
    public func inject(into configuration: URLSessionConfiguration) {
        var protocolClasses = configuration.protocolClasses ?? []
        if !protocolClasses.contains(where: { $0 == MonitorURLProtocol.self }) {
            protocolClasses.insert(MonitorURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = protocolClasses
    }

    public static func capture(for receiver: Receiver) {
        Self.default.capture(for: receiver)
    }

    public static func stop() {
        Self.default.stop()
    }

    public static func inject(into configuration: URLSessionConfiguration) {
        Self.default.inject(into: configuration)
    }

    static func emit(_ event: NetworkEvent) {
        Task {
            await EventTransport.shared.send(event)
        }
    }
}

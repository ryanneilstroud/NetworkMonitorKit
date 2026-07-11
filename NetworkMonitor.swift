import Foundation

public enum Periscope {
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

        public static func localhost(port: Int = 61337) -> Receiver {
            device(host: "localhost", port: port)
        }
    }

    private static var configured = false

    public static func capture(for receivers: Receiver...) {
        guard !receivers.isEmpty else { return }
        capture(for: receivers)
    }

    public static func capture(for receivers: [Receiver]) {
        guard !configured else { return }
        guard let primaryReceiver = receivers.first else { return }

        configured = true
        URLProtocol.registerClass(MonitorURLProtocol.self)
        Task {
            await EventTransport.shared.configure(host: primaryReceiver.host, port: primaryReceiver.port)
        }
    }

    public static func stop() {
        URLProtocol.unregisterClass(MonitorURLProtocol.self)
        Task {
            await EventTransport.shared.stop()
        }
        configured = false
    }

    // Use this helper for explicit session setups where URLProtocol registration
    // doesn't get inherited automatically.
    public static func inject(into configuration: URLSessionConfiguration) {
        var protocolClasses = configuration.protocolClasses ?? []
        if !protocolClasses.contains(where: { $0 == MonitorURLProtocol.self }) {
            protocolClasses.insert(MonitorURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = protocolClasses
    }

    static func emit(_ event: NetworkEvent) {
        Task {
            await EventTransport.shared.send(event)
        }
    }
}

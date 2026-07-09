import Foundation

public enum Periscope {
    private static var configured = false

    public static func capture(host: String = "localhost", port: UInt16 = 61337) {
        guard !configured else { return }
        configured = true
        URLProtocol.registerClass(MonitorURLProtocol.self)
        Task {
            await EventTransport.shared.configure(host: host, port: port)
        }
    }

    @available(*, deprecated, renamed: "capture(host:port:)")
    public static func observe(host: String = "localhost", port: UInt16 = 61337) {
        capture(host: host, port: port)
    }

    @available(*, deprecated, renamed: "capture(host:port:)")
    public static func start(host: String = "localhost", port: UInt16 = 61337) {
        capture(host: host, port: port)
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

@available(*, deprecated, renamed: "Periscope")
public typealias NetworkMonitor = Periscope

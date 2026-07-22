import Foundation

protocol SocketEventRecording: Sendable {
    func record(_ event: SocketCaptureEvent)
}

struct DisabledSocketEventRecorder: SocketEventRecording {
    func record(_ event: SocketCaptureEvent) {}
}

struct TransportSocketEventRecorder: SocketEventRecording {
    static let defaultMaximumPayloadBytes = 64 * 1024

    private let maximumPayloadBytes: Int
    private let send: @Sendable (SocketTransportEvent) -> Void

    init(
        maximumPayloadBytes: Int = Self.defaultMaximumPayloadBytes,
        send: @escaping @Sendable (SocketTransportEvent) -> Void = { event in
            Task { await EventTransport.shared.send(event) }
        }
    ) {
        self.maximumPayloadBytes = maximumPayloadBytes
        self.send = send
    }

    func record(_ event: SocketCaptureEvent) {
        send(SocketTransportEvent(captureEvent: event, maximumPayloadBytes: maximumPayloadBytes))
    }
}

#if DEBUG
final class SocketEventRecorderSpy: SocketEventRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [SocketCaptureEvent] = []

    var events: [SocketCaptureEvent] {
        lock.withLock { recordedEvents }
    }

    func record(_ event: SocketCaptureEvent) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}
#endif

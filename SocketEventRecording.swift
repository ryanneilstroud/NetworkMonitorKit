import Foundation

protocol SocketEventRecording: Sendable {
    func record(_ event: SocketCaptureEvent)
}

struct DisabledSocketEventRecorder: SocketEventRecording {
    func record(_ event: SocketCaptureEvent) {}
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

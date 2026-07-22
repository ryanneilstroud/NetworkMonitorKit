import Foundation

final class WebSocketCaptureCoordinator: @unchecked Sendable {
    static let shared = WebSocketCaptureCoordinator()

    private struct TaskState {
        let connectionID: UUID
        let endpoint: String
        var hasRecordedCreation: Bool
        var hasRecordedResume: Bool
    }

    private let lock = NSLock()
    private var isRecordingEnabled = false
    private var recorder: any SocketEventRecording = DisabledSocketEventRecorder()
    private var taskStates: [ObjectIdentifier: TaskState] = [:]

    init() {}

    func enable(recorder: any SocketEventRecording = DisabledSocketEventRecorder()) {
        lock.withLock {
            self.recorder = recorder
            isRecordingEnabled = true
        }
    }

    func disable() {
        lock.withLock {
            isRecordingEnabled = false
            recorder = DisabledSocketEventRecorder()
            taskStates.removeAll(keepingCapacity: false)
        }
    }

    func recordResume(for task: URLSessionWebSocketTask) {
        recordLifecycle(.resumed, for: task, onlyOnce: true)
    }

    func recordCancel(for task: URLSessionWebSocketTask) {
        recordLifecycle(.cancelled, for: task, onlyOnce: false)
    }

    func recordClose(
        for task: URLSessionWebSocketTask,
        code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard let context = context(for: task) else { return }
        context.recorder.record(
            SocketCaptureEvent(
                connectionID: context.state.connectionID,
                kind: .closed,
                endpoint: context.state.endpoint,
                closeCode: code.rawValue,
                closeReason: reason
            )
        )
    }

    func recordPing(for task: URLSessionWebSocketTask) {
        recordLifecycle(.ping, for: task, onlyOnce: false)
    }

    func recordOutgoing(_ message: URLSessionWebSocketTask.Message, for task: URLSessionWebSocketTask) {
        recordMessage(message, direction: .outbound, for: task)
    }

    func recordIncoming(_ message: URLSessionWebSocketTask.Message, for task: URLSessionWebSocketTask) {
        recordMessage(message, direction: .inbound, for: task)
    }

    func recordFailure(_ error: Error, for task: URLSessionWebSocketTask) {
        guard let context = context(for: task) else { return }
        context.recorder.record(
            SocketCaptureEvent(
                connectionID: context.state.connectionID,
                kind: .failed,
                endpoint: context.state.endpoint,
                errorDescription: error.localizedDescription
            )
        )
    }

    private func recordMessage(
        _ message: URLSessionWebSocketTask.Message,
        direction: SocketCaptureEvent.Direction,
        for task: URLSessionWebSocketTask
    ) {
        guard let context = context(for: task) else { return }
        let payload: SocketCaptureEvent.Payload
        switch message {
        case .string(let value):
            payload = .text(value)
        case .data(let value):
            payload = .binary(value)
        @unknown default:
            return
        }
        context.recorder.record(
            SocketCaptureEvent(
                connectionID: context.state.connectionID,
                kind: .message,
                direction: direction,
                endpoint: context.state.endpoint,
                payload: payload
            )
        )
    }

    private func recordLifecycle(
        _ kind: SocketCaptureEvent.Kind,
        for task: URLSessionWebSocketTask,
        onlyOnce: Bool
    ) {
        let output: (any SocketEventRecording, TaskState, Bool)? = lock.withLock {
            guard isRecordingEnabled else { return nil }
            let key = ObjectIdentifier(task)
            var state = taskStates[key] ?? makeState(for: task)
            if kind == .resumed, onlyOnce, state.hasRecordedResume {
                return nil
            }
            if kind == .resumed {
                state.hasRecordedResume = true
            }
            let shouldRecordCreation = !state.hasRecordedCreation
            state.hasRecordedCreation = true
            taskStates[key] = state
            return (recorder, state, shouldRecordCreation)
        }
        guard let output else { return }
        if output.2 {
            output.0.record(
                SocketCaptureEvent(
                    connectionID: output.1.connectionID,
                    kind: .created,
                    endpoint: output.1.endpoint
                )
            )
        }
        output.0.record(
            SocketCaptureEvent(
                connectionID: output.1.connectionID,
                kind: kind,
                endpoint: output.1.endpoint
            )
        )
    }

    private func context(
        for task: URLSessionWebSocketTask
    ) -> (recorder: any SocketEventRecording, state: TaskState)? {
        let output: (any SocketEventRecording, TaskState, Bool)? = lock.withLock {
            guard isRecordingEnabled else { return nil }
            let key = ObjectIdentifier(task)
            var state = taskStates[key] ?? makeState(for: task)
            let shouldRecordCreation = !state.hasRecordedCreation
            state.hasRecordedCreation = true
            taskStates[key] = state
            return (recorder, state, shouldRecordCreation)
        }
        guard let output else { return nil }
        if output.2 {
            output.0.record(
                SocketCaptureEvent(
                    connectionID: output.1.connectionID,
                    kind: .created,
                    endpoint: output.1.endpoint
                )
            )
        }
        return (output.0, output.1)
    }

    private func makeState(for task: URLSessionWebSocketTask) -> TaskState {
        let requestURL = task.originalRequest?.url ?? task.currentRequest?.url
        return TaskState(
            connectionID: UUID(),
            endpoint: webSocketEndpoint(from: requestURL),
            hasRecordedCreation: false,
            hasRecordedResume: false
        )
    }

    private func webSocketEndpoint(from url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<unknown>"
        }
        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: break
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

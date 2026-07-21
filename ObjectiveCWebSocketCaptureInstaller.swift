import Foundation
import ObjectiveC.runtime

public enum WebSocketCaptureAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

final class ObjectiveCWebSocketCaptureInstaller: @unchecked Sendable {
    static let shared = ObjectiveCWebSocketCaptureInstaller()

    private typealias MessageCompletion = @convention(block) (AnyObject?, Error?) -> Void
    private typealias ErrorCompletion = @convention(block) (Error?) -> Void
    private typealias SendImplementation = @convention(c) (
        AnyObject,
        Selector,
        AnyObject,
        ErrorCompletion
    ) -> Void
    private typealias ReceiveImplementation = @convention(c) (
        AnyObject,
        Selector,
        MessageCompletion
    ) -> Void
    private typealias PingImplementation = @convention(c) (
        AnyObject,
        Selector,
        ErrorCompletion
    ) -> Void
    private typealias CloseImplementation = @convention(c) (
        AnyObject,
        Selector,
        Int,
        NSData?
    ) -> Void
    private typealias VoidImplementation = @convention(c) (AnyObject, Selector) -> Void

    private let lock = NSLock()
    private var installedClasses: Set<ObjectIdentifier> = []
    private(set) var availability: WebSocketCaptureAvailability = .unavailable(reason: "Not installed")

    private init() {}

    func install() -> WebSocketCaptureAvailability {
        lock.withLock {
            let probe = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1/")!)
            guard let concreteClass = object_getClass(probe) else {
                let result = WebSocketCaptureAvailability.unavailable(reason: "Foundation returned no WebSocket task class")
                availability = result
                return result
            }
            let classID = ObjectIdentifier(concreteClass)
            if installedClasses.contains(classID) {
                availability = .available
                return .available
            }

            do {
                try installHooks(on: concreteClass)
                installedClasses.insert(classID)
                availability = .available
                return .available
            } catch {
                let result = WebSocketCaptureAvailability.unavailable(reason: error.localizedDescription)
                availability = result
                return result
            }
        }
    }

    private func installHooks(on concreteClass: AnyClass) throws {
        try installSendHook(on: concreteClass)
        try installReceiveHook(on: concreteClass)
        try installPingHook(on: concreteClass)
        try installCloseHook(on: concreteClass)
        try installVoidHook(
            on: concreteClass,
            selector: #selector(URLSessionTask.resume),
            record: { task in WebSocketCaptureCoordinator.shared.recordResume(for: task) }
        )
        try installVoidHook(
            on: concreteClass,
            selector: #selector(URLSessionTask.cancel),
            record: { task in WebSocketCaptureCoordinator.shared.recordCancel(for: task) }
        )
    }

    private func installSendHook(on concreteClass: AnyClass) throws {
        let selector = NSSelectorFromString("sendMessage:completionHandler:")
        let original: SendImplementation = try implementation(on: concreteClass, selector: selector)
        let block: @convention(block) (AnyObject, AnyObject, ErrorCompletion) -> Void = { object, message, completion in
            if let task = object as? URLSessionWebSocketTask,
               let bridgedMessage = Self.bridgeMessage(message) {
                WebSocketCaptureCoordinator.shared.recordOutgoing(bridgedMessage, for: task)
            }
            original(object, selector, message, completion)
        }
        try replace(on: concreteClass, selector: selector, with: block)
    }

    private func installReceiveHook(on concreteClass: AnyClass) throws {
        let selector = NSSelectorFromString("receiveMessageWithCompletionHandler:")
        let original: ReceiveImplementation = try implementation(on: concreteClass, selector: selector)
        let block: @convention(block) (AnyObject, @escaping MessageCompletion) -> Void = { object, completion in
            let wrapped: MessageCompletion = { message, error in
                if let task = object as? URLSessionWebSocketTask {
                    if let message, let bridgedMessage = Self.bridgeMessage(message) {
                        WebSocketCaptureCoordinator.shared.recordIncoming(bridgedMessage, for: task)
                    }
                    if let error {
                        WebSocketCaptureCoordinator.shared.recordFailure(error, for: task)
                    }
                }
                completion(message, error)
            }
            original(object, selector, wrapped)
        }
        try replace(on: concreteClass, selector: selector, with: block)
    }

    private func installPingHook(on concreteClass: AnyClass) throws {
        let selector = NSSelectorFromString("sendPingWithPongReceiveHandler:")
        let original: PingImplementation = try implementation(on: concreteClass, selector: selector)
        let block: @convention(block) (AnyObject, ErrorCompletion) -> Void = { object, completion in
            if let task = object as? URLSessionWebSocketTask {
                WebSocketCaptureCoordinator.shared.recordPing(for: task)
            }
            original(object, selector, completion)
        }
        try replace(on: concreteClass, selector: selector, with: block)
    }

    private func installCloseHook(on concreteClass: AnyClass) throws {
        let selector = NSSelectorFromString("cancelWithCloseCode:reason:")
        let original: CloseImplementation = try implementation(on: concreteClass, selector: selector)
        let block: @convention(block) (AnyObject, Int, NSData?) -> Void = { object, rawCode, reason in
            if let task = object as? URLSessionWebSocketTask,
               let code = URLSessionWebSocketTask.CloseCode(rawValue: rawCode) {
                WebSocketCaptureCoordinator.shared.recordClose(for: task, code: code, reason: reason as Data?)
            }
            original(object, selector, rawCode, reason)
        }
        try replace(on: concreteClass, selector: selector, with: block)
    }

    private func installVoidHook(
        on concreteClass: AnyClass,
        selector: Selector,
        record: @escaping @Sendable (URLSessionWebSocketTask) -> Void
    ) throws {
        let original: VoidImplementation = try implementation(on: concreteClass, selector: selector)
        let block: @convention(block) (AnyObject) -> Void = { object in
            if let task = object as? URLSessionWebSocketTask {
                record(task)
            }
            original(object, selector)
        }
        try replace(on: concreteClass, selector: selector, with: block)
    }

    private func implementation<T>(on concreteClass: AnyClass, selector: Selector) throws -> T {
        guard let method = class_getInstanceMethod(concreteClass, selector) else {
            throw WebSocketCaptureInstallationError.missingSelector(NSStringFromSelector(selector))
        }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }

    private static func bridgeMessage(_ message: AnyObject) -> URLSessionWebSocketTask.Message? {
        guard let object = message as? NSObject else { return nil }
        if let text = object.value(forKey: "string") as? String {
            return .string(text)
        }
        if let data = object.value(forKey: "data") as? Data {
            return .data(data)
        }
        return nil
    }

    private func replace<Block>(on concreteClass: AnyClass, selector: Selector, with block: Block) throws {
        guard let method = class_getInstanceMethod(concreteClass, selector),
              let typeEncoding = method_getTypeEncoding(method) else {
            throw WebSocketCaptureInstallationError.missingSelector(NSStringFromSelector(selector))
        }
        let replacement = imp_implementationWithBlock(block as Any)
        class_replaceMethod(concreteClass, selector, replacement, typeEncoding)
    }
}

private enum WebSocketCaptureInstallationError: LocalizedError {
    case missingSelector(String)

    var errorDescription: String? {
        switch self {
        case .missingSelector(let selector):
            return "Native WebSocket task does not expose expected selector: \(selector)"
        }
    }
}

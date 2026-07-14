import Foundation
import Network
import XCTest
import Darwin
@testable import PeriscopeKit

final class EventTransportReconnectTests: XCTestCase {
    func testReconnectsAndFlushesBufferedEventsWhenServerBecomesAvailable() async throws {
        let port = try await reserveAvailablePort()
        let transport = EventTransport()

        await transport.configure(host: "127.0.0.1", port: port)
        let requestID = UUID()
        await transport.send(makeEvent(requestID: requestID))

        try await Task.sleep(nanoseconds: 400_000_000)

        let server = try LineCaptureServer(port: port)
        await server.start()

        let eventPayload = try await waitForEventPayload(
            requestID: requestID,
            in: server,
            timeoutNanoseconds: 8_000_000_000
        )
        XCTAssertEqual(eventPayload["type"] as? String, "event")

        let allPayloads = try await waitForPayloadCount(2, in: server, timeoutNanoseconds: 8_000_000_000)
        let types = allPayloads.compactMap { $0["type"] as? String }
        XCTAssertTrue(types.contains("clientHello"))
        XCTAssertTrue(types.contains("event"))

        await transport.stop()
        await server.stop()
    }

    func testFlushesBufferedEventsInOrderWhenServerBecomesAvailable() async throws {
        let port = try await reserveAvailablePort()
        let transport = EventTransport()
        await transport.configure(host: "127.0.0.1", port: port)

        let requestIDs = [UUID(), UUID(), UUID()]
        for requestID in requestIDs {
            await transport.send(makeEvent(requestID: requestID))
        }
        try await Task.sleep(nanoseconds: 400_000_000)

        let server = try LineCaptureServer(port: port)
        await server.start()
        let payloads = try await waitForPayloadCount(4, in: server, timeoutNanoseconds: 8_000_000_000)
        let receivedRequestIDs = payloads.compactMap { payload -> UUID? in
            guard payload["type"] as? String == "event" else { return nil }
            guard let event = payload["event"] as? [String: Any] else { return nil }
            guard let requestIDString = event["requestID"] as? String else { return nil }
            return UUID(uuidString: requestIDString)
        }

        XCTAssertEqual(receivedRequestIDs, requestIDs)
        await transport.stop()
        await server.stop()
    }

    private func makeEvent(requestID: UUID) -> NetworkEvent {
        NetworkEvent(
            kind: .started,
            requestID: requestID,
            request: NetworkEvent.RequestPayload(
                url: "https://example.com/path",
                method: "GET",
                headers: [:],
                body: nil
            ),
            response: nil
        )
    }

    private func reserveAvailablePort() async throws -> UInt16 {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        defer {
            close(socketFD)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0)
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(socketFD, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var assigned = sockaddr_in()
        var assignedLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                getsockname(socketFD, pointer, &assignedLength)
            }
        }
        guard nameResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        return UInt16(bigEndian: assigned.sin_port)
    }

    private func waitForPayloadCount(
        _ count: Int,
        in server: LineCaptureServer,
        timeoutNanoseconds: UInt64
    ) async throws -> [[String: Any]] {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let payloads = try decodePayloads(await server.lines())
            if payloads.count >= count {
                return payloads
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for \(count) payloads.")
        return []
    }

    private func waitForEventPayload(
        requestID: UUID,
        in server: LineCaptureServer,
        timeoutNanoseconds: UInt64
    ) async throws -> [String: Any] {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let payloads = try decodePayloads(await server.lines())
            if let match = payloads.first(where: { payload in
                guard payload["type"] as? String == "event" else { return false }
                guard let event = payload["event"] as? [String: Any] else { return false }
                guard let requestIDString = event["requestID"] as? String else { return false }
                return UUID(uuidString: requestIDString) == requestID
            }) {
                return match
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for event payload for requestID \(requestID.uuidString).")
        return [:]
    }

    private func decodePayloads(_ lines: [Data]) throws -> [[String: Any]] {
        try lines.compactMap { line in
            guard !line.isEmpty else { return nil }
            let json = try JSONSerialization.jsonObject(with: line)
            return json as? [String: Any]
        }
    }
}

private actor LineCaptureServer {
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var receivedLines: [Data] = []

    init(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "LineCaptureServer", code: 1)
        }
        listener = try NWListener(using: .tcp, on: nwPort)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.accept(connection)
            }
            connection.start(queue: .global())
        }

        listener.stateUpdateHandler = { _ in }
        listener.start(queue: .global())
    }

    func stop() {
        listener.cancel()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
    }

    func lines() -> [Data] {
        receivedLines
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                var rolling = buffer
                if let data, !data.isEmpty {
                    rolling.append(data)
                    await self.consumeLines(from: &rolling)
                }
                if isComplete || error != nil {
                    await self.remove(connection)
                    return
                }
                await self.receive(on: connection, buffer: rolling)
            }
        }
    }

    private func consumeLines(from buffer: inout Data) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer.prefix(upTo: newlineIndex))
            buffer.removeSubrange(...newlineIndex)
            if !lineData.isEmpty {
                receivedLines.append(lineData)
            }
        }
    }

    private func remove(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
}

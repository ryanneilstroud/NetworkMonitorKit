import Foundation
import Testing
@testable import PeriscopeKit

@Suite("HTTP capture request filtering")
struct MonitorURLProtocolTests {
    @Test("accepts regular HTTP requests")
    func acceptsHTTP() throws {
        // Given
        let request = URLRequest(url: try #require(URL(string: "https://example.com/resource")))

        // When
        let canHandle = MonitorURLProtocol.canInit(with: request)

        // Then
        #expect(canHandle)
    }

    @Test("rejects native WebSocket URL schemes", arguments: ["ws", "wss"])
    func rejectsWebSocketSchemes(_ scheme: String) throws {
        // Given
        let request = URLRequest(url: try #require(URL(string: "\(scheme)://example.com/socket")))

        // When
        let canHandle = MonitorURLProtocol.canInit(with: request)

        // Then
        #expect(!canHandle)
    }

    @Test("rejects an HTTP WebSocket upgrade handshake")
    func rejectsHTTPWebSocketUpgrade() throws {
        // Given
        var request = URLRequest(url: try #require(URL(string: "http://example.com/socket")))
        request.setValue("WebSocket", forHTTPHeaderField: "Upgrade")

        // When
        let canHandle = MonitorURLProtocol.canInit(with: request)

        // Then
        #expect(!canHandle)
    }
}

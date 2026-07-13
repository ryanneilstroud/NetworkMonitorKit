import Foundation

final class MonitorURLProtocol: URLProtocol {
    private static let handledKey = "NetworkMonitorHandledKey"
    private static let requestIDKey = "NetworkMonitorRequestIDKey"

    private var dataTask: URLSessionDataTask?
    private var session: URLSession?
    private var startedAt: Date?
    private var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        startedAt = Date()
        let requestID = UUID()

        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        URLProtocol.setProperty(requestID.uuidString, forKey: Self.requestIDKey, in: mutableRequest)
        let requestBodyData = materializeRequestBody(from: mutableRequest)
        let forwardedRequest = mutableRequest as URLRequest

        let requestPayload = NetworkEvent.RequestPayload(
            url: forwardedRequest.url?.absoluteString ?? "<unknown>",
            method: forwardedRequest.httpMethod ?? "GET",
            headers: forwardedRequest.allHTTPHeaderFields ?? [:],
            body: decodeBody(requestBodyData)
        )
        Periscope.emit(
            NetworkEvent(kind: .started, requestID: requestID, request: requestPayload, response: nil)
        )

        let configuration = URLSessionConfiguration.default
        var protocolClasses = configuration.protocolClasses ?? []
        protocolClasses.removeAll { $0 == MonitorURLProtocol.self }
        configuration.protocolClasses = protocolClasses

        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.session = session
        dataTask = session.dataTask(with: forwardedRequest) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }
            guard let self else { return }
            self.session = nil
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
                self.responseData.append(data)
            }

            let responsePayload = NetworkEvent.ResponsePayload(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                headers: stringDictionary(from: (response as? HTTPURLResponse)?.allHeaderFields),
                body: decodeBody(data ?? self.responseData),
                error: error?.localizedDescription,
                durationMS: self.durationMS()
            )
            Periscope.emit(
                NetworkEvent(kind: .completed, requestID: requestID, request: requestPayload, response: responsePayload)
            )

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func durationMS() -> Int {
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt) * 1000.0)
    }

    private func materializeRequestBody(from request: NSMutableURLRequest) -> Data? {
        if let body = request.httpBody, body.isEmpty == false {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        guard let streamBody = readData(from: stream), streamBody.isEmpty == false else { return nil }

        // Replace stream body with concrete data so URLSession can still send the payload after inspection.
        request.httpBodyStream = nil
        request.httpBody = streamBody
        return streamBody
    }

    private func readData(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}

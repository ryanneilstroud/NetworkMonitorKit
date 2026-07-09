import Foundation

final class MonitorURLProtocol: URLProtocol {
    private static let handledKey = "NetworkMonitorHandledKey"
    private static let requestIDKey = "NetworkMonitorRequestIDKey"

    private var dataTask: URLSessionDataTask?
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

        let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest ?? NSMutableURLRequest()
        mutableRequest.url = request.url
        if let method = request.httpMethod {
            mutableRequest.httpMethod = method
        }
        mutableRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
        mutableRequest.httpBody = request.httpBody
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        URLProtocol.setProperty(requestID.uuidString, forKey: Self.requestIDKey, in: mutableRequest)
        let forwardedRequest = mutableRequest as URLRequest

        let requestPayload = NetworkEvent.RequestPayload(
            url: forwardedRequest.url?.absoluteString ?? "<unknown>",
            method: forwardedRequest.httpMethod ?? "GET",
            headers: forwardedRequest.allHTTPHeaderFields ?? [:],
            body: decodeBody(forwardedRequest.httpBody)
        )
        Periscope.emit(
            NetworkEvent(kind: .started, requestID: requestID, request: requestPayload, response: nil)
        )

        let configuration = URLSessionConfiguration.default
        var protocolClasses = configuration.protocolClasses ?? []
        protocolClasses.removeAll { $0 == MonitorURLProtocol.self }
        configuration.protocolClasses = protocolClasses

        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        dataTask = session.dataTask(with: forwardedRequest) { [weak self] data, response, error in
            guard let self else { return }
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
    }

    private func durationMS() -> Int {
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt) * 1000.0)
    }
}

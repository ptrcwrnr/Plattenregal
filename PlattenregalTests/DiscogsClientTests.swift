import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

nonisolated final class DiscogsStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let code = Int(url.lastPathComponent) ?? 200
        if code == 901 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = [401, 429, 500].contains(code) ? code : 200
        var body = #"{"id":1,"title":"Test"}"#
        if code == 900 { body = "not json" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension AllTests {
    struct DiscogsClientTests {
        @Test func missingToken() async {
            let error = await #expect(throws: DiscogsError.self) { try await DiscogsAPIClient.stubbed(DiscogsStubProtocol.self, token: nil).release(id: 1) }
            guard case .missingToken = error else { Issue.record("Unexpected: \(String(describing: error))"); return }
        }
        /// What `DiscogsStubProtocol` answers for `/releases/<code>`, and the
        /// error the client makes of it (after its repeats, where it repeats).
        @Test(arguments: [(401, "unauthorized"), (429, "rateLimited(1)"), (500, "http(500)"), (900, "invalidResponse"), (901, "offline")])
        func failuresBecomeTheAppsOwnErrors(code: Int, expected: String) async {
            let error = await #expect(throws: DiscogsError.self) { try await DiscogsAPIClient.stubbed(DiscogsStubProtocol.self).release(id: code) }
            #expect(error.map { String(describing: $0) } == expected)
        }
    }
}

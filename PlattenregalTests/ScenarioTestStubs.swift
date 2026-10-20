import Foundation
@testable import Plattenregal

/// Discogs as seen by the scenarios: `online` answers with a two-record
/// collection (with tracklists and value), otherwise every request fails
/// like a Mac without network. `throttleFirst` answers the first request
/// with 429 and Retry-After: 1.
nonisolated final class ScenarioProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var online = true
    nonisolated(unsafe) static var throttleFirst = false
    nonisolated(unsafe) static var requests = 0
    private static let lock = NSLock()
    static func reset(online: Bool, throttleFirst: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        self.online = online; self.throttleFirst = throttleFirst; requests = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requests += 1
        let online = Self.online, throttle = Self.throttleFirst && Self.requests == 1
        Self.lock.unlock()
        guard online else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        func item(_ id: Int) -> String {
            #"{"id":\#(id),"instance_id":\#(id),"folder_id":1,"date_added":"2026-09-20","rating":0,"basic_information":{"id":\#(id),"title":"Album \#(id)","artists":[{"id":1,"name":"Artist","join":""}]}}"#
        }
        let path = url.path
        let body: String
        var status = 200
        var headers: [String: String] = [:]
        if throttle { status = 429; headers["Retry-After"] = "1"; body = "{}" }
        else if path == "/oauth/identity" { body = #"{"id":7,"username":"scenario"}"# }
        else if path.hasSuffix("/collection/folders") { body = #"{"folders":[{"id":0,"name":"All","count":2},{"id":1,"name":"Uncategorized","count":2}]}"# }
        else if path.hasSuffix("/collection/value") { body = #"{"minimum":"€10.00","median":"€20.00","maximum":"€30.00"}"# }
        else if path.hasSuffix("/releases") { body = #"{"pagination":{"page":1,"pages":1,"per_page":100,"items":2},"releases":[\#(item(1)),\#(item(2))]}"# }
        else if path.hasPrefix("/releases/") {
            body = #"{"id":\#(url.lastPathComponent),"title":"Album","tracklist":[{"position":"A1","title":"Intro","duration":"1:00"}]}"#
        } else { status = 404; body = "{}" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

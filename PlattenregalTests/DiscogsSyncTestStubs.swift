import Foundation
import Testing
import Synchronization
@testable import Plattenregal

nonisolated final class SyncPaginationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let page = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
        let body: String
        if url.path == "/oauth/identity" { body = request.value(forHTTPHeaderField: "Authorization") == "Discogs token=wantfailure" ? #"{"id":7,"username":"wantfailure"}"# : #"{"id":7,"username":"fixture"}"# }
        else if url.path.hasSuffix("/folders") { body = #"{"folders":[{"id":1,"name":"Changed","count":2}]}"# }
        else {
            if (page == 2 && url.path.contains("/fixture/")) || (url.path.contains("/wantfailure/") && url.path.hasSuffix("/wants")) {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            if let empty = ["/empty0/": 0, "/empty1/": 1].first(where: { url.path.contains($0.key) }) {
                let key = url.path.hasSuffix("/wants") ? "wants" : "releases"
                respond(#"{"pagination":{"page":1,"pages":\#(empty.value),"per_page":100,"items":0},"\#(key)":[]}"#, url)
                return
            }
            let id = url.path.contains("/duplicate/") ? 1 : page
            let item = """
            {"id":\(id),"instance_id":\(id),"folder_id":1,"date_added":"2026-09-20","rating":0,"basic_information":{"id":\(id),"title":"Album","artists":[]}}
            """
            let key = url.path.hasSuffix("/wants") ? "wants" : "releases"
            body = """
            {"pagination":{"page":\(page),"pages":2,"per_page":1,"items":2},"\(key)":[\(item)]}
            """
        }
        respond(body, url)
    }
    private func respond(_ body: String, _ url: URL) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// `/releases/<status>` answers with that HTTP status; 200 with a one-track release and its video.
nonisolated final class TracklistStatusProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let status = Int(url.lastPathComponent) ?? 500
        let body = status == 200 ? #"{"id":200,"title":"Album","tracklist":[{"position":"A1","title":"Intro","duration":"1:00"}],"videos":[{"uri":"https://www.youtube.com/watch?v=intro","title":"Artist - Intro"}]}"# : "{}"
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// One record in the collection; the request for its value tells the test
/// and is never answered, a release request is counted.
nonisolated final class CancelDuringValueProtocol: URLProtocol, @unchecked Sendable {
    static let onValueRequest = Mutex<(@Sendable () -> Void)?>(nil)
    static let releaseRequests = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        if url.path == "/oauth/identity" { body = #"{"id":7,"username":"fixture"}"# }
        else if url.path.hasSuffix("/collection/folders") { body = #"{"folders":[{"id":0,"name":"All","count":1},{"id":1,"name":"Uncategorized","count":1}]}"# }
        else if url.path.hasSuffix("/collection/value") { Self.onValueRequest.withLock { $0 }?(); return }
        else if url.path.hasPrefix("/releases/") { Self.releaseRequests.withLock { $0 += 1 }; body = #"{"id":1,"tracklist":[]}"# }
        else {
            body = #"{"pagination":{"page":1,"pages":1,"per_page":100,"items":1},"releases":[{"id":1,"instance_id":1,"folder_id":1,"date_added":"2026-09-20","basic_information":{"id":1,"title":"Album","artists":[]}}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Release requests: IDs below 1000 are refused (403), the others answered
/// with an empty tracklist. Counts the release requests.
nonisolated final class RefusingReleasesProtocol: URLProtocol, @unchecked Sendable {
    static let releaseRequests = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.releaseRequests.withLock { $0 += 1 }
        let id = Int(url.lastPathComponent) ?? 0
        let status = id < 1000 ? 403 : 200
        let body = status == 200 ? #"{"id":\#(id),"tracklist":[]}"# : "{}"
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

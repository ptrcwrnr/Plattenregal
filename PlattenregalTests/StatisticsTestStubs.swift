import Foundation
@testable import Plattenregal

nonisolated final class StatisticsRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func append(_ path: String) { lock.lock(); defer { lock.unlock() }; entries.append(path) }
    func clear() { lock.lock(); defer { lock.unlock() }; entries.removeAll() }
}
nonisolated final class StatisticsHook: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    func set(_ action: @escaping @Sendable () -> Void) { lock.lock(); defer { lock.unlock() }; self.action = action }
    func take() -> (@Sendable () -> Void)? { lock.lock(); defer { lock.unlock() }; let taken = action; action = nil; return taken }
}
nonisolated final class StatisticsURLProtocol: URLProtocol, @unchecked Sendable {
    static let log = StatisticsRequestLog()
    /// Runs once on the next value request, before it is answered.
    static let beforeValue = StatisticsHook()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!; Self.log.append(url.path)
        let body: String
        if url.path.hasSuffix("/folders") { body = #"{"folders":[{"id":1,"name":"All","count":1}]}"# }
        else if url.path.contains("/collection/folders/") { body = #"{"pagination":{"page":1,"pages":1,"per_page":100,"items":1},"releases":[{"id":42,"instance_id":1,"folder_id":1,"date_added":"2026-09-20T12:00:00+02:00","rating":0,"basic_information":{"id":42,"title":"Synced","artists":[]}}]}"# }
        else if url.path.hasSuffix("/value") { Self.beforeValue.take()?(); body = #"{"minimum":"€50.00","median":"€100.00","maximum":"€200.00"}"# }
        else { body = "{}" }
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = token == "Discogs token=denied" || (token == "Discogs token=denied-value" && url.path.hasSuffix("/value")) ? 403 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

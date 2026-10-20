import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

/// Parent of all suites. Serialized like XCTest was: the suites share
/// URLProtocol stubs and app singletons.
@Suite(.serialized) enum AllTests {}

extension DiscogsAPIClient {
    /// A client answered by `stub` instead of Discogs. Without the second
    /// between requests and the pauses before a repeat: they only made the
    /// tests wait. A `Retry-After` from the stub is still waited out.
    static func stubbed(_ stub: URLProtocol.Type, token: String? = "fixture") -> DiscogsAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [stub]
        return DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { token }, spacing: 0, retryPause: 0.01)
    }
}

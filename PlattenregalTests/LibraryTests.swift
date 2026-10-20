import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    struct LibraryTests {
        func fixture() throws -> (ModelContainer, [Shelf], PositionService) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            return (container, shelves, PositionService(context: container.mainContext))
        }
        @discardableResult func add(_ service: PositionService, _ shelf: Shelf, _ artist: String, _ title: String = "Album", at position: Int? = nil) throws -> RecordCopy {
            try service.insert(release: Release(artist: artist, title: title), shelf: shelf, position: position ?? shelf.copies.count + 1)
        }
    }
}

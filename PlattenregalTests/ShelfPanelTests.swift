import Foundation
import SwiftData
import Testing
@testable import Plattenregal

extension AllTests {
    /// The panel over the shelf page and its round buttons: a button closes
    /// only its own panel, any other panel is switched (see `ShelfPanel.button`).
    @MainActor struct ShelfPanelTests {
        private func compartment() throws -> (ModelContainer, Shelf) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let cabinet = try #require(try CabinetService(context: container.mainContext).cabinets().first)
            return (container, cabinet.orderedShelves[0])
        }

        @Test func historyBelongsToItsButton() {
            #expect(ShelfPanel.history(ShelfHistoryRequest()).button == .history)
        }

        @Test func onlyTheRackWideAssignmentBelongsToSortingIn() throws {
            let (container, shelf) = try compartment()
            defer { _ = container }
            #expect(ShelfPanel.assignment(ShelfAssignmentSession(shelf: nil)).button == .sortingIn)
            // "Platte hinzufügen" of a compartment: "Einsortieren" switches to its own panel.
            #expect(ShelfPanel.assignment(ShelfAssignmentSession(shelf: shelf)).button == nil)
        }

        @Test func sortCheckBelongsToNoButton() throws {
            let (container, shelf) = try compartment()
            defer { _ = container }
            #expect(ShelfPanel.sortCheck(ShelfSortCheckRequest(shelf: shelf)).button == nil)
        }

        /// The panel fades over when its id changes: each opening is a new one.
        @Test func everyOpeningIsANewPanel() {
            let session = ShelfAssignmentSession(shelf: nil)
            #expect(ShelfPanel.assignment(session).id == session.id)
            #expect(ShelfPanel.history(ShelfHistoryRequest()).id != ShelfPanel.history(ShelfHistoryRequest()).id)
        }
    }
}

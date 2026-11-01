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

extension AllTests {
    /// The search behind the record in the menu bar: a click holds a match
    /// instead of opening the main window, the place reads "Pos. x von y",
    /// and the panel sits at the top in the middle or in the top right corner.
    @MainActor struct QuickSearchTests {
        private func search(_ titles: [String]) throws -> (ModelContainer, ShelfQuickSearchModel, Shelf) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let cabinet = try #require(try CabinetService(context: container.mainContext).cabinets().first)
            let shelf = cabinet.orderedShelves[0]
            let positions = PositionService(context: container.mainContext)
            for title in titles {
                try positions.insert(release: Release(artist: "Abba", title: title), shelf: shelf, position: shelf.copies.count + 1)
            }
            return (container, ShelfQuickSearchModel(context: container.mainContext), shelf)
        }

        @Test func aClickHoldsTheMatchAgainstThePointer() throws {
            let (container, model, _) = try search(["Arrival", "Gold", "Voulez-Vous"])
            defer { _ = container }
            model.text = "abba"
            let ids = model.matches.map(\.id)
            try #require(ids.count == 3)
            #expect(model.highlighted == ids[0] && model.pinned == nil)

            // The pointer picks while nothing is held.
            model.hover(model.matches[1])
            #expect(model.highlighted == ids[1])

            // Held: the pointer passing over other rows leaves it.
            model.togglePin(model.matches[1])
            #expect(model.pinned == ids[1] && model.highlighted == ids[1])
            model.hover(model.matches[2])
            model.hover(model.matches[0])
            #expect(model.highlighted == ids[1])

            // Clicking another row holds that one; the arrow keys take the hold along.
            model.togglePin(model.matches[0])
            #expect(model.pinned == ids[0] && model.highlighted == ids[0])
            model.move(1)
            #expect(model.pinned == ids[1] && model.highlighted == ids[1])

            // Again on the held one: lets go, the pointer picks again.
            model.togglePin(model.matches[1])
            #expect(model.pinned == nil)
            model.hover(model.matches[2])
            #expect(model.highlighted == ids[2])
        }

        @Test func aHoldEndsWhenTheMatchIsGoneOrTheSearchStartsAgain() throws {
            let (container, model, _) = try search(["Arrival", "Gold"])
            defer { _ = container }
            model.text = "abba"
            let gold = try #require(model.matches.first { $0.release?.displayTitle == "Gold" })
            model.togglePin(gold)

            // Still a match: still held, and the one the rack shows.
            model.text = "abba gold"
            #expect(model.pinned == gold.id && model.highlighted == gold.id)
            // No longer a match: let go.
            model.text = "abba arrival"
            #expect(model.pinned == nil)
            #expect(model.highlighted == model.matches.first?.id)

            model.togglePin(try #require(model.matches.first))
            model.text = ""
            #expect(model.pinned == nil && model.highlighted == nil)
            model.text = "abba"
            model.togglePin(try #require(model.matches.first))
            model.reset()
            #expect(model.pinned == nil)
        }

        /// "Pos. 2 von 3": out of the records in the compartment; one that
        /// only belongs there would be one more; never fewer than the position.
        @Test func thePlaceSaysOutOfHowMany() throws {
            let (container, model, shelf) = try search(["Arrival", "Gold", "Voulez-Vous"])
            defer { _ = container }
            #expect(shelf.recordCount() == 3)
            let first = try #require(shelf.copies.first)
            #expect(shelf.recordCount(excluding: first.id) == 2)
            #expect(shelf.positionText(2) == String(localized: "Pos. \(2) von \(3)"))
            #expect(shelf.positionText(4, joining: true) == String(localized: "Pos. \(4) von \(4)"))
            #expect(shelf.positionText(9) == String(localized: "Pos. \(9) von \(9)"))

            model.text = "gold"
            let gold = try #require(model.matches.first)
            let place = try #require(model.place(of: gold))
            #expect(place.placed && place.position == gold.positionInShelf)
        }

        /// A MacBook screen, the menu bar 33 pt high: in the middle under the
        /// notch, or in the corner as far from the right edge as from the bar –
        /// from the Dock's edge when it sits on the right.
        @Test func thePanelSitsInTheMiddleOrInTheTopRightCorner() {
            let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
            let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
            let width: CGFloat = 320, gap = AppStyle.tightSpacing
            let middle = ShelfQuickSearch.surfaceCorner(width: width, screen: screen, visible: visible, position: .center)
            #expect(middle == CGPoint(x: 756 - 160, y: 949 - gap))
            let corner = ShelfQuickSearch.surfaceCorner(width: width, screen: screen, visible: visible, position: .topRight)
            #expect(corner == CGPoint(x: 1512 - width - gap, y: 949 - gap))
            let besideDock = CGRect(x: 0, y: 0, width: 1450, height: 949)
            #expect(ShelfQuickSearch.surfaceCorner(width: width, screen: screen, visible: besideDock, position: .topRight).x == 1450 - width - gap)
            // A second screen to the left: its own middle and corner.
            let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
            let leftVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
            let leftMiddle: CGFloat = -1920 + 960 - 160
            #expect(ShelfQuickSearch.surfaceCorner(width: width, screen: left, visible: leftVisible, position: .center).x == leftMiddle)
            #expect(ShelfQuickSearch.surfaceCorner(width: width, screen: left, visible: leftVisible, position: .topRight).x == -width - gap)
        }
    }
}

import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    struct DiscogsNameTests {
        @Test func dropsNumericDisambiguationOnly() {
            #expect(DiscogsName.clean("Systematic (3)") == "Systematic")
            #expect(DiscogsName.clean("Moby (2) & Kid (3), Other (14)") == "Moby & Kid, Other")
            // Words in parentheses and numbers that aren't a separate suffix stay.
            #expect(DiscogsName.clean("Kontor Records (Germany)") == "Kontor Records (Germany)")
            #expect(DiscogsName.clean("(3)") == "(3)")
            #expect(DiscogsName.clean("Sash!(2)") == "Sash!(2)")
            #expect(DiscogsName.clean("Systematic") == "Systematic")
        }
        /// The hand-written scan behaves exactly like the regex it replaced.
        @Test func matchesTheFormerRegex() {
            let inputs = ["Systematic (3)", "Moby (2) & Kid (3), Other (14)", "A  (2)", "A (2)(3)", "A (2) (3)", "A (2),B", "A (2)x",
                          "A (x)", "A ()", "A (12", " (3)", "(3) A", "A\t(4)\nB", "A (2) ", "Ä (٣)", "A ((2))", "A (2)) ", "",
                          "Sigur Rós (5), Björk (2) & Røyksopp", "Name (1999)", "A (2)\u{00A0}B", "A\u{00A0}(2)", "A (²)", "A (1٣2), B", "A\r\n(2)"]
            for input in inputs {
                #expect(DiscogsName.clean(input) == input.replacing(/\s+\(\d+\)(?=\s|,|$)/, with: ""), "\(input.debugDescription)")
            }
        }
    }
}

extension AllTests {
    struct DisplaySettingsTests {
        @Test func coverSizeStaysInRange() {
            #expect(DisplaySettings.coverSize(.nan) == DisplaySettings.defaultCoverSize)
            #expect(DisplaySettings.coverSize(.infinity) == DisplaySettings.defaultCoverSize)
            #expect(DisplaySettings.coverSize(-50) == DisplaySettings.coverSizes.first)
            #expect(DisplaySettings.coverSize(10_000) == DisplaySettings.coverSizes.last)
            // A value of the old slider: the nearest step.
            #expect(DisplaySettings.coverSize(180) == 195)
            #expect(DisplaySettings.coverSize(155) == 155)
            #expect(DisplaySettings.coverSize(155, offset: 1) == 195)
            #expect(DisplaySettings.coverSize(195, offset: 1) == 195)
            #expect(DisplaySettings.coverSize(125, offset: -1) == 125)
        }

        @Test func columnCountSurvivesOddMinimum() {
            #expect(CoverGrid.columnCount(available: 800, minimum: -8) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: .nan) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: 0) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: 155) == 4)
        }
    }
}

extension AllTests {
    struct AccentContrastTests {
        /// Contrast of white text on the accent (selected segments, primary
        /// buttons), in light and dark mode.
        private func contrastWithWhite(_ color: Color, _ name: NSAppearance.Name) -> Double {
            var rgb = NSColor.white
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
            }
            func linear(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
            return 1.05 / (luminance + 0.05)
        }

        @Test func whiteTextStaysReadableOnEveryAccent() {
            for choice in AccentChoice.allCases where choice != .system {
                for name in [NSAppearance.Name.aqua, .darkAqua] {
                    let contrast = contrastWithWhite(choice.color, name)
                    #expect(contrast >= 3, "\(choice.title) in \(name.rawValue): \(contrast)")
                }
            }
        }
    }
}

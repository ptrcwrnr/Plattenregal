import AppKit
import SwiftUI
import Foundation
import Testing
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

extension AllTests {
    /// The tags' dots (`AppStyle.markColor`): fixed per design and for light
    /// and dark. Each must stand out from the list's surface by at least 3:1
    /// (WCAG for graphics), checked against the lighter and the darker of the
    /// surfaces a list lies on, and the three must differ from each other.
    struct TagColorContrastTests {
        private static func srgb(_ color: Color, _ name: NSAppearance.Name) -> NSColor {
            var resolved = NSColor.clear
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                resolved = NSColor(color).usingColorSpace(.sRGB) ?? .clear
            }
            return resolved
        }
        private static func luminance(_ c: NSColor) -> Double {
            func linear(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
            let (la, lb) = (luminance(a), luminance(b))
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
        private static func hex(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, alpha: 1)
        }

        /// The surfaces behind a list: Modern's glass over a light or dark
        /// window (white and a light gray / two dark grays), the paper
        /// designs' card and page.
        private static func surfaces(_ design: SignatureDesign, _ name: NSAppearance.Name) -> [NSColor] {
            guard design.isPaper else {
                return name == .darkAqua ? [hex(0x1E1E1E), hex(0x323236)] : [hex(0xFFFFFF), hex(0xE8EBF0)]
            }
            return [srgb(design.paperColors.surface, name), srgb(design.paperColors.paper, name)]
        }

        @Test func everyDotStandsOutFromTheListInEveryDesignAndMode() {
            for design in SignatureDesign.allCases {
                for name in design.isAlwaysDark ? [NSAppearance.Name.darkAqua] : [.aqua, .darkAqua] {
                    for mark in RecordMark.allCases {
                        let dot = Self.srgb(AppStyle.markColor(mark, design: design), name)
                        for surface in Self.surfaces(design, name) {
                            let value = Self.contrast(dot, surface)
                            #expect(value >= 3, "\(design.logName) \(name.rawValue) \(mark.title): \(value)")
                        }
                    }
                }
            }
        }

        @Test func theThreeDotsDifferFromEachOther() {
            func distance(_ a: NSColor, _ b: NSColor) -> Double {
                let d = [a.redComponent - b.redComponent, a.greenComponent - b.greenComponent, a.blueComponent - b.blueComponent]
                return sqrt(d.map { Double($0 * $0) }.reduce(0, +))
            }
            for design in SignatureDesign.allCases {
                for name in design.isAlwaysDark ? [NSAppearance.Name.darkAqua] : [.aqua, .darkAqua] {
                    let dots = RecordMark.allCases.map { Self.srgb(AppStyle.markColor($0, design: design), name) }
                    for i in dots.indices { for j in dots.indices where j > i {
                        #expect(distance(dots[i], dots[j]) >= 0.3, "\(design.logName) \(name.rawValue) \(i)/\(j)")
                    } }
                }
            }
        }
    }
}

extension AllTests {
    struct GridSecondaryClickTests {
        /// The grid built anew in one go: the new cell reports before the old
        /// one of the same record disappears. The record stays right-clickable.
        @Test func lateDisappearKeepsNewerCell() {
            let clicks = GridSecondaryClicks<Int>()
            let frame = CGRect(x: 0, y: 0, width: 100, height: 120)
            let old = UUID(), new = UUID()
            clicks.report(1, frame: frame, owner: old)
            clicks.report(1, frame: frame, owner: new)
            clicks.remove(1, owner: old)
            #expect(clicks.cell(at: CGPoint(x: 50, y: 60))?.id == 1)
            clicks.remove(1, owner: new)
            #expect(clicks.cell(at: CGPoint(x: 50, y: 60)) == nil)
        }

        @Test func findsTheCellUnderThePoint() {
            let clicks = GridSecondaryClicks<Int>()
            clicks.report(1, frame: CGRect(x: 0, y: 0, width: 100, height: 120), owner: UUID())
            clicks.report(2, frame: CGRect(x: 110, y: 0, width: 100, height: 120), owner: UUID())
            clicks.report(3, frame: .zero, owner: UUID())
            #expect(clicks.cell(at: CGPoint(x: 150, y: 10))?.id == 2)
            #expect(clicks.cell(at: CGPoint(x: 105, y: 10)) == nil)
            #expect(clicks.cell(at: .zero)?.id != 3)
        }
    }
}

import SwiftUI
import AppKit

/// The colors of the paper designs, Klassisch and Vinyl. Both are built the
/// same way (matte surfaces, a colored band under the toolbar, see
/// `AppStyle.isAtelier`) and differ only in these colors. Modern's accent
/// and ambient choices stay intact. Part of the app and of the widget, so it
/// depends on nothing else.
///
/// A class, not a struct: `AtelierPalette` hands out one color per read,
/// several times in every cover cell, and a struct was copied whole each
/// time (all its colors retained and released; measured about half the cost
/// of a read).
nonisolated final class ClassicColors: Sendable {
    /// The window behind every page.
    let paper: Color
    /// Cards, panels, fields.
    let surface: Color
    /// A shade between the two: tracks of switches, the selected row.
    let soft: Color
    let ink: Color
    let muted: Color
    let border: Color
    /// The band under the toolbar and the round buttons on it.
    let petrol: Color
    /// Links, symbols, the tint of controls.
    let accent: Color
    /// The highlight: main buttons, the selection rim, the dot in the preview.
    let gold: Color
    let goldForeground: Color
    /// The chosen option on the band, and its label.
    let toolbarSelection: Color
    let toolbarInk: Color
    /// Labels on the band that aren't chosen (toolbar, the widget's band).
    let bandLabel: Color
    /// Glyphs and titles on the band itself (round buttons, column headers).
    let bandInk: Color
    let shadow: Color
    /// Signal colors (see `AppStyle.successColor` …).
    let success: Color
    let warning: Color
    let error: Color
    /// The tags' dots (`TagDots`): „Gesucht“, „Verkauf“, „Nicht in der
    /// Collection“ – each readable on the list's surface (at least 3:1,
    /// see `TagColorContrastTests`) and set apart from the others.
    let tagMissing: Color
    let tagSale: Color
    let tagSold: Color
    /// Categories in charts (statistics).
    let chart: [Color]

    init(paper: Color,
         surface: Color,
         soft: Color,
         ink: Color,
         muted: Color,
         border: Color,
         petrol: Color,
         accent: Color,
         gold: Color,
         goldForeground: Color,
         toolbarSelection: Color,
         toolbarInk: Color,
         bandLabel: Color,
         bandInk: Color,
         shadow: Color,
         success: Color,
         warning: Color,
         error: Color,
         tagMissing: Color,
         tagSale: Color,
         tagSold: Color,
         chart: [Color]) {
        self.paper = paper
        self.surface = surface
        self.soft = soft
        self.ink = ink
        self.muted = muted
        self.border = border
        self.petrol = petrol
        self.accent = accent
        self.gold = gold
        self.goldForeground = goldForeground
        self.toolbarSelection = toolbarSelection
        self.toolbarInk = toolbarInk
        self.bandLabel = bandLabel
        self.bandInk = bandInk
        self.shadow = shadow
        self.success = success
        self.warning = warning
        self.error = error
        self.tagMissing = tagMissing
        self.tagSale = tagSale
        self.tagSold = tagSold
        self.chart = chart
    }

    /// Klassisch: the icon's paper, petrol and label gold, light and dark.
    static let klassisch = ClassicColors(
        paper: PaletteColor.adaptive(0xF4EFE5, 0x172B32),
        surface: PaletteColor.adaptive(0xFFFAF2, 0x213940),
        soft: PaletteColor.adaptive(0xEBE5DA, 0x1B3138),
        ink: PaletteColor.adaptive(0x233A3E, 0xEEE8DB),
        muted: PaletteColor.adaptive(0x63716E, 0xB3C1BE),
        border: PaletteColor.adaptive(0xDCD7CB, 0x3E5155),
        petrol: PaletteColor.adaptive(0x1D4C5B, 0x123C4B),
        accent: PaletteColor.adaptive(0x246074, 0xA5CCCF),
        gold: PaletteColor.rgb(0xE2B660),
        goldForeground: PaletteColor.rgb(0x293C39),
        toolbarSelection: PaletteColor.rgb(0xF4EFE5),
        toolbarInk: PaletteColor.rgb(0x233A3E),
        bandLabel: Color.white.opacity(0.8),
        bandInk: PaletteColor.rgb(0xF4EFE5),
        shadow: PaletteColor.adaptive(0x1D3C42, 0x000000).opacity(0.08),
        // Moss, ochre, brick.
        success: PaletteColor.adaptive(0x3E7A55, 0x8FC4A0),
        warning: PaletteColor.adaptive(0xA8711C, 0xE2B660),
        error: PaletteColor.adaptive(0xA9443A, 0xE69384),
        // Brick, a dusty blue apart from the petrol, old gold – the gold
        // leans to yellow, so it never reads as a second brick.
        tagMissing: PaletteColor.adaptive(0xB2453A, 0xF07A70),
        tagSale: PaletteColor.adaptive(0x3A6EA5, 0x8DB7E8),
        tagSold: PaletteColor.adaptive(0xA08410, 0xE3CB5A),
        // Petrol and gold first, then muted earth tones that sit well on
        // cream and on the dark paper.
        chart: [0x2F6F80, 0xD9A441, 0x7FA38A, 0xC2714F, 0x5B7DA6, 0x8C5A7A, 0xA8A060].map(PaletteColor.rgb))

    /// Vinyl: cool graphite with light blue, always dark (the app then shows
    /// itself dark, see `SignatureDesign.isAlwaysDark`), so one value each.
    static let vinyl = ClassicColors(
        paper: PaletteColor.rgb(0x22272F),
        surface: PaletteColor.rgb(0x2C313B),
        soft: PaletteColor.rgb(0x272C35),
        ink: PaletteColor.rgb(0xEDEDEE),
        muted: PaletteColor.rgb(0x9CA2AD),
        border: PaletteColor.rgb(0x454D5A),
        petrol: PaletteColor.rgb(0x2C313B),
        accent: PaletteColor.rgb(0xA3BDFA),
        gold: PaletteColor.rgb(0x6B84C7),
        goldForeground: PaletteColor.rgb(0xFFFFFF),
        toolbarSelection: PaletteColor.rgb(0x6B84C7),
        toolbarInk: PaletteColor.rgb(0xFFFFFF),
        bandLabel: Color.white.opacity(0.8),
        bandInk: PaletteColor.rgb(0xEDEDEE),
        shadow: Color.black.opacity(0.25),
        // Mint, sand, coral – soft enough for the dark graphite.
        success: PaletteColor.rgb(0x8FD0A6),
        warning: PaletteColor.rgb(0xE2C07E),
        error: PaletteColor.rgb(0xE9A499),
        // Coral, the light blue of the accent, a yellow sand – bright enough
        // on graphite and well apart from the coral.
        tagMissing: PaletteColor.rgb(0xF27A70),
        tagSale: PaletteColor.rgb(0x8FB0FA),
        tagSold: PaletteColor.rgb(0xE3CC66),
        // Blues first, then cool, muted tones.
        chart: [0x6B84C7, 0xA3BDFA, 0x7FB8A8, 0xD59A7A, 0xA88FD8, 0xD9B26F, 0x8FA0B3].map(PaletteColor.rgb))
}

/// The designs' fixed colors: an sRGB hex value, or one color each for
/// light and dark, resolved by the appearance they are drawn in. The one
/// place for both, used by the paper palettes, Modern's tag colors, the
/// cover mat and the shelf's wells.
nonisolated enum PaletteColor {
    static func rgb(_ hex: UInt32) -> Color { Color(nsColor: ns(hex)) }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color { adaptive(ns(light), ns(dark)) }
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    private static func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The colors of the paper design in use. `colors` comes from the target:
/// the app follows the chosen design (and reading it lets views redraw when
/// it changes), the widget always shows Klassisch.
enum AtelierPalette {
    static var paper: Color { colors.paper }
    static var surface: Color { colors.surface }
    static var soft: Color { colors.soft }
    static var ink: Color { colors.ink }
    static var muted: Color { colors.muted }
    static var border: Color { colors.border }
    static var petrol: Color { colors.petrol }
    static var accent: Color { colors.accent }
    static var gold: Color { colors.gold }
    static var goldForeground: Color { colors.goldForeground }
    static var toolbarSelection: Color { colors.toolbarSelection }
    static var toolbarInk: Color { colors.toolbarInk }
    static var bandLabel: Color { colors.bandLabel }
    static var bandInk: Color { colors.bandInk }
    static var shadow: Color { colors.shadow }
    static var success: Color { colors.success }
    static var warning: Color { colors.warning }
    static var error: Color { colors.error }
    static var chart: [Color] { colors.chart }
}

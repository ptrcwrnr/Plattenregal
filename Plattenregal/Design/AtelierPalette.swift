import SwiftUI
import AppKit

/// The colors of the paper designs, Klassisch and Vinyl. Both are built the
/// same way (matte surfaces, a colored band under the toolbar, see
/// `AppStyle.isAtelier`) and differ only in these colors. Modern's accent
/// and ambient choices stay intact. Part of the app and of the widget, so it
/// depends on nothing else.
nonisolated struct ClassicColors: Sendable {
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
    /// Categories in charts (statistics).
    let chart: [Color]

    /// Klassisch: the icon's paper, petrol and label gold, light and dark.
    static let klassisch = ClassicColors(
        paper: adaptive(0xF4EFE5, 0x172B32),
        surface: adaptive(0xFFFAF2, 0x213940),
        soft: adaptive(0xEBE5DA, 0x1B3138),
        ink: adaptive(0x233A3E, 0xEEE8DB),
        muted: adaptive(0x63716E, 0xB3C1BE),
        border: adaptive(0xDCD7CB, 0x3E5155),
        petrol: adaptive(0x1D4C5B, 0x123C4B),
        accent: adaptive(0x246074, 0xA5CCCF),
        gold: rgb(0xE2B660),
        goldForeground: rgb(0x293C39),
        toolbarSelection: rgb(0xF4EFE5),
        toolbarInk: rgb(0x233A3E),
        bandLabel: Color.white.opacity(0.8),
        bandInk: rgb(0xF4EFE5),
        shadow: adaptive(0x1D3C42, 0x000000).opacity(0.08),
        // Moss, ochre, brick.
        success: adaptive(0x3E7A55, 0x8FC4A0),
        warning: adaptive(0xA8711C, 0xE2B660),
        error: adaptive(0xA9443A, 0xE69384),
        // Petrol and gold first, then muted earth tones that sit well on
        // cream and on the dark paper.
        chart: [0x2F6F80, 0xD9A441, 0x7FA38A, 0xC2714F, 0x5B7DA6, 0x8C5A7A, 0xA8A060].map(rgb))

    /// Vinyl: cool graphite with light blue, always dark (the app then shows
    /// itself dark, see `SignatureDesign.isAlwaysDark`), so one value each.
    static let vinyl = ClassicColors(
        paper: rgb(0x22272F),
        surface: rgb(0x2C313B),
        soft: rgb(0x272C35),
        ink: rgb(0xEDEDEE),
        muted: rgb(0x9CA2AD),
        border: rgb(0x454D5A),
        petrol: rgb(0x2C313B),
        accent: rgb(0xA3BDFA),
        gold: rgb(0x6B84C7),
        goldForeground: rgb(0xFFFFFF),
        toolbarSelection: rgb(0x6B84C7),
        toolbarInk: rgb(0xFFFFFF),
        bandLabel: Color.white.opacity(0.8),
        bandInk: rgb(0xEDEDEE),
        shadow: Color.black.opacity(0.25),
        // Mint, sand, coral – soft enough for the dark graphite.
        success: rgb(0x8FD0A6),
        warning: rgb(0xE2C07E),
        error: rgb(0xE9A499),
        // Blues first, then cool, muted tones.
        chart: [0x6B84C7, 0xA3BDFA, 0x7FB8A8, 0xD59A7A, 0xA88FD8, 0xD9B26F, 0x8FA0B3].map(rgb))

    private static func nsRGB(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
    private static func rgb(_ hex: UInt32) -> Color { Color(nsColor: nsRGB(hex)) }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsRGB(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
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

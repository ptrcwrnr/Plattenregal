import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSV

nonisolated enum CSVWriter {
    /// RFC 4180 with a byte order mark, so Excel opens umlauts correctly.
    /// Semicolons are what Excel expects with German regional settings.
    static func data(for table: ExportTable, delimiter: ExportDelimiter) -> Data {
        var text = line(table.columns, delimiter: delimiter.character)
        for row in table.rows { text += line(row.values, delimiter: delimiter.character) }
        return Data("\u{FEFF}".utf8) + Data(text.utf8)
    }

    static func line(_ values: [String], delimiter: Character) -> String {
        values.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) + "\r\n"
    }

    static func escape(_ value: String, delimiter: Character) -> String {
        let value = defused(value)
        let needsQuotes = value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r")
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Excel and Numbers evaluate cells starting with = + - @ as formulas:
    /// an artist like "-M-" would turn into an error, a note like
    /// "=HYPERLINK(…)" into a live link. A leading apostrophe keeps them text.
    /// Plain numbers ("-5") stay untouched.
    static func defused(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) || first == "\t" || first == "\r" else { return value }
        if first == "-" || first == "+", Double(value) != nil { return value }
        return "'" + value
    }
}

// MARK: - PDF

/// A printable list on A4 landscape: title, then the records as a table.
/// In shelf order every compartment gets its own heading; long values are
/// cut to one line so the list stays scannable.
nonisolated enum PDFListWriter {
    private static let page = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 15
    private static let sectionHeight: CGFloat = 26

    /// Columns and their share of the line width; only those present in the table are drawn.
    private static let layout: [(name: String, width: CGFloat)] = [
        (ExportColumn.position, 0.05), (ExportColumn.artist, 0.21), (ExportColumn.title, 0.23),
        (ExportColumn.year, 0.04), (ExportColumn.label, 0.15), (ExportColumn.catalogNumber, 0.11),
        (ExportColumn.format, 0.15), (ExportColumn.shelf, 0.08),
    ]

    static func data(for table: ExportTable, title: String, subtitle: String) throws -> Data {
        let grouped = table.rows.contains { $0.section != nil }
        // Grouped by shelf, the heading already names the shelf.
        let columns = layout.filter { grouped ? $0.name != ExportColumn.shelf : $0.name != ExportColumn.position }
            .compactMap { column in table.column(column.name).map { (column.name, column.width, $0) } }
        let total = columns.reduce(0) { $0 + $1.1 }
        let width = page.width - 2 * margin
        var x = margin
        let cells = columns.map { name, share, index in
            defer { x += width * share / total }
            return (name: name, index: index, x: x, width: width * share / total - 6)
        }

        let data = NSMutableData()
        var box = page
        let info = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Plattenregal"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, info) else { throw CocoaError(.fileWriteUnknown) }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }

        var pageNumber = 0
        var y: CGFloat = 0
        let bottom = page.height - margin - 14

        func endPage() {
            draw(String(localized: "Seite \(pageNumber)"), in: CGRect(x: margin, y: page.height - margin, width: width, height: 12),
                 font: .systemFont(ofSize: 8), color: .secondaryLabelColor, alignment: .right)
            pdf.endPDFPage()
        }
        func beginPage() {
            if pageNumber > 0 { endPage() }
            pageNumber += 1
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: page.height)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            y = margin
            if pageNumber == 1 {
                draw(title, in: CGRect(x: margin, y: y, width: width, height: 24), font: .boldSystemFont(ofSize: 18))
                y += 24
                draw(subtitle, in: CGRect(x: margin, y: y, width: width, height: 14), font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
                y += 24
            }
            header()
        }
        func header() {
            for cell in cells {
                draw(cell.name, in: CGRect(x: cell.x, y: y, width: cell.width, height: rowHeight), font: .boldSystemFont(ofSize: 8), color: .secondaryLabelColor)
            }
            y += rowHeight
            pdf.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)
            pdf.fill(CGRect(x: margin, y: y - 3, width: width, height: 0.5))
        }
        func section(_ title: String) {
            y += 6
            draw(title, in: CGRect(x: margin, y: y, width: width, height: 16), font: .boldSystemFont(ofSize: 11))
            y += sectionHeight - 6
        }

        beginPage()
        var currentSection: String?
        var stripe = false
        for row in table.rows {
            let startsSection = grouped && row.section != currentSection
            // Keep a heading together with its first record.
            if y + rowHeight + (startsSection ? sectionHeight : 0) > bottom {
                beginPage()
                if grouped, !startsSection, let currentSection { section(currentSection + String(localized: " (Fortsetzung)")) }
            }
            if startsSection {
                currentSection = row.section
                section(row.section ?? "")
                stripe = false
            }
            if stripe {
                pdf.setFillColor(NSColor.black.withAlphaComponent(0.04).cgColor)
                pdf.fill(CGRect(x: margin - 4, y: y - 1, width: width + 8, height: rowHeight))
            }
            stripe.toggle()
            for cell in cells {
                let value = cell.name == ExportColumn.shelf ? row.place ?? row.values[cell.index] : row.values[cell.index]
                draw(value, in: CGRect(x: cell.x, y: y, width: cell.width, height: rowHeight), font: .systemFont(ofSize: 8.5))
            }
            y += rowHeight
        }
        if table.rows.isEmpty {
            draw(String(localized: "Keine Einträge"), in: CGRect(x: margin, y: y + 8, width: width, height: 14), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        }
        endPage()
        pdf.closePDF()
        return data as Data
    }

    private static func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor = .black,
                             alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        // Fixed colours: a printout has no dark mode.
        let resolved = color == .secondaryLabelColor ? NSColor(white: 0.4, alpha: 1) : color
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: resolved, .paragraphStyle: style])
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

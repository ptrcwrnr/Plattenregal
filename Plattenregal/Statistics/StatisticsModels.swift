import Foundation
import SwiftData

nonisolated struct DiscogsMoney: Equatable, Sendable {
    let amount: Decimal
    let currency: String
    static func parse(_ raw: String) throws -> Self {
        let upper = raw.uppercased()
        let codes = ["EUR", "USD", "GBP", "CAD", "AUD", "JPY", "CHF", "SEK", "NOK", "DKK", "NZD", "BRL", "MXN", "ZAR", "HKD", "SGD", "PLN", "CZK", "HUF", "INR", "KRW", "TRY", "CNY"]
        let currency: String
        if let code = codes.first(where: { upper.contains($0) }) { currency = code }
        else if raw.contains("€") { currency = "EUR" }
        else if raw.contains("£") { currency = "GBP" }
        else if upper.contains("CA$") || upper.contains("C$") { currency = "CAD" }
        else if upper.contains("A$") || upper.contains("AU$") { currency = "AUD" }
        else if upper.contains("NZ$") { currency = "NZD" }
        else if upper.contains("HK$") { currency = "HKD" }
        else if upper.contains("US$") { currency = "USD" }
        else if upper.contains("S$") { currency = "SGD" }
        else if upper.contains("R$") { currency = "BRL" }
        else if upper.contains("MX$") { currency = "MXN" }
        else if raw.contains("$") { currency = "USD" }
        else if raw.contains("¥") { currency = "JPY" }
        else { throw DiscogsError.invalidResponse }
        var number = raw.filter { "0123456789.,-".contains($0) }
        guard number.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:[.,][0-9]{3})+)(?:[.,][0-9]{1,2})?$"#, options: .regularExpression) != nil else { throw DiscogsError.invalidResponse }
        let comma = number.lastIndex(of: ","), dot = number.lastIndex(of: ".")
        let separator: Character?
        if let comma, let dot { separator = comma > dot ? "," : "." }
        else if let index = comma ?? dot {
            let trailing = number.distance(from: number.index(after: index), to: number.endIndex)
            separator = trailing == 1 || trailing == 2 ? number[index] : nil
        } else { separator = nil }
        if let separator, let last = number.lastIndex(of: separator) {
            let integer = number[..<last].filter { $0 != "," && $0 != "." }
            let fraction = number[number.index(after: last)...]
            number = integer + "." + fraction
        } else { number = number.filter { $0 != "," && $0 != "." } }
        guard let amount = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")), amount >= 0 else { throw DiscogsError.invalidResponse }
        return Self(amount: amount, currency: currency)
    }
    static func format(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currency).locale(locale))
    }
}
nonisolated struct DiscogsCollectionValue: Decodable, Sendable {
    let minimum: DiscogsMoney
    let median: DiscogsMoney
    let maximum: DiscogsMoney
    enum CodingKeys: String, CodingKey { case minimum, median, maximum }
    init(minimum: DiscogsMoney, median: DiscogsMoney, maximum: DiscogsMoney) throws {
        guard minimum.currency == median.currency, median.currency == maximum.currency,
              minimum.amount <= median.amount, median.amount <= maximum.amount else { throw DiscogsError.invalidResponse }
        self.minimum = minimum; self.median = median; self.maximum = maximum
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(minimum: DiscogsMoney.parse(c.decode(String.self, forKey: .minimum)),
                      median: DiscogsMoney.parse(c.decode(String.self, forKey: .median)),
                      maximum: DiscogsMoney.parse(c.decode(String.self, forKey: .maximum)))
    }
}

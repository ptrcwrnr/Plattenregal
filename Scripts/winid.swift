// Prints the window number of Plattenregal's largest on-screen window
// (for `screencapture -l`). Used by tour-screenshots.sh.
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "Plattenregal" && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ window: [String: Any]) -> Double {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}
if let largest = mine.max(by: { area($0) < area($1) }), let number = largest[kCGWindowNumber as String] { print(number) }

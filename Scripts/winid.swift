// Prints the window number of Plattenregal's largest on-screen window
// (for `screencapture -l`). Used by tour-screenshots.sh. With a process ID
// as argument only that process's windows count (the demo, not an
// installed Plattenregal that happens to be open).
import CoreGraphics
import Foundation
let argument = CommandLine.arguments.dropFirst().first
let pid = argument.flatMap { Int($0) }
// Asked for a process that isn't running: no window rather than any window.
if argument != nil && pid == nil { exit(1) }
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Plattenregal" && ($0[kCGWindowLayer as String] as? Int) == 0
        && (pid == nil || ($0[kCGWindowOwnerPID as String] as? Int) == pid)
}
func area(_ window: [String: Any]) -> Double {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}
if let largest = mine.max(by: { area($0) < area($1) }), let number = largest[kCGWindowNumber as String] { print(number) }

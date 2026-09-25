import AppKit
import Darwin
import MachO
import OSLog

/// The app's own protocol, one line per event with date and time, so it can
/// always be traced what happened when – for reading afterwards, not shown in
/// the app. Written to `Application Support/Plattenregal/Logs/Plattenregal.log`
/// in the app's container (the previous file is kept as `Plattenregal.old.log`).
///
/// Records launches and how the last session ended, opening and migrating the
/// store, syncs, token changes, every change to shelves and copies, exports,
/// shelf backups (automatic and to a file) and restores, every error the user
/// is shown (with its technical detail) and crashes with their call stack.
/// Never the Discogs token.
///
/// A crash is written as a block "==== ABSTURZ … ====" with the app version
/// and the raw call stack; the next launch adds a readable line saying which
/// crash it was and when. The start line carries the load address, so the
/// addresses can be resolved later:
/// `atos -o Plattenregal.app/Contents/MacOS/Plattenregal -l <Ladeadresse> <Adressen>`.
nonisolated enum AppLog {
    enum Level: String { case info = "INFO ", warning = "WARN ", error = "ERROR", fault = "FAULT" }

    static func info(_ category: String, _ message: String) { write(.info, category, message) }
    static func warning(_ category: String, _ message: String) { write(.warning, category, message) }
    static func error(_ category: String, _ message: String) { write(.error, category, message) }

    /// Location of the log, for reading it.
    static var fileURL: URL? { directory?.appendingPathComponent("Plattenregal.log") }
    static var logDirectory: URL? { directory }
    private static var oldFileURL: URL? { directory?.appendingPathComponent("Plattenregal.old.log") }

    /// Both files, oldest first, for passing on when something went wrong.
    static func exportData() -> Data {
        lock.lock(); defer { lock.unlock() }
        var data = Data()
        for url in [oldFileURL, fileURL].compactMap({ $0 }) {
            if let contents = try? Data(contentsOf: url) { data.append(contents) }
        }
        return data
    }

    /// Starts the protocol afresh (the crash handler keeps writing to the
    /// same file, so it is emptied rather than deleted).
    static func clear() {
        lock.lock()
        if let oldFileURL { try? FileManager.default.removeItem(at: oldFileURL) }
        if let fileURL { try? Data().write(to: fileURL) }
        lock.unlock()
        info("App", "Protokoll geleert")
    }

    // MARK: Session

    /// Once at launch: rotates the file, notes how the previous session ended
    /// and installs the crash handlers.
    static func startSession(details: String, version: String) {
        guard isEnabled, let directory, let fileURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Before rotating: the crash block sits at the end of the current file.
        let crash = previousCrash(in: fileURL)
        let old = directory.appendingPathComponent("Plattenregal.old.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > Int(rotationSize) {
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: fileURL, to: old)
        }
        write(.info, "App", "──── Start · Version \(version) · \(details) · Ladeadresse \(loadAddress)")
        if let crash {
            let when = crash.date.map { " am \($0.formatted(date: .numeric, time: .standard))" } ?? ""
            write(.error, "App", "Die vorige Sitzung ist abgestürzt\(when): \(crash.reason). Der Ablauf steht im Block „ABSTURZ“ direkt vor diesem Start.")
        } else if let previous = markerPID(), !isRunning(previous) {
            write(.warning, "App", "Die vorige Sitzung wurde nicht normal beendet – ohne Absturz-Eintrag, also vermutlich in Xcode gestoppt, zwangsweise beendet oder der Mac ging aus.")
        }
        // The marker names this process: when switching into or out of the
        // demo, the old instance is still quitting while the new one starts.
        let own = ProcessInfo.processInfo.processIdentifier
        FileManager.default.createFile(atPath: runningMarker.path, contents: Data("\(own)".utf8))
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            write(.info, "App", "Beendet")
            // Only its own marker – a newer instance may have written it meanwhile.
            if markerPID() == own { try? FileManager.default.removeItem(at: runningMarker) }
        }
        installCrashHandlers(logPath: fileURL.path, version: version)
    }

    /// This instance may not open the collection (another one has it): the
    /// running marker goes back to that one, so how *its* session ends is
    /// still told at the next launch – this instance quitting won't remove it.
    static func handMarkerBack(to pid: Int32) {
        guard isEnabled, directory != nil else { return }
        FileManager.default.createFile(atPath: runningMarker.path, contents: Data("\(pid)".utf8))
    }

    /// Process that wrote the running marker; `0` for markers of older
    /// versions (empty file), `nil` when there is none.
    private static func markerPID() -> Int32? {
        guard let data = FileManager.default.contents(atPath: runningMarker.path) else { return nil }
        return Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Still alive – the previous session hasn't ended yet, it is quitting
    /// right now (relaunch into or out of the demo), so nothing went wrong.
    private static func isRunning(_ pid: Int32) -> Bool {
        pid > 0 && pid != ProcessInfo.processInfo.processIdentifier
            // EPERM: the process exists, the sandbox just may not signal it.
            && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// The main program's address in memory this session (it changes with
    /// every launch), needed to resolve the addresses of a crash.
    private static var loadAddress: String {
        guard let header = _dyld_get_image_header(0) else { return "?" }
        return "0x" + String(UInt(bitPattern: header), radix: 16)
    }

    /// The crash block of the last session, if it ended in one: after the
    /// last start line, "==== ABSTURZ: <reason> · Unix-Zeit <seconds> ====".
    static func previousCrash(in url: URL) -> (reason: String, date: Date?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // The end is enough: a crash is the last thing a session writes.
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let session = text.range(of: "──── Start", options: .backwards).map { text[$0.upperBound...] } ?? text[...]
        guard let marker = session.range(of: "==== ABSTURZ: ", options: .backwards) else { return nil }
        let line = session[marker.upperBound...].prefix { $0 != "\n" }
        let parts = line.components(separatedBy: " · Unix-Zeit ")
        let seconds = parts.count > 1 ? Double(parts[1].prefix { $0.isNumber }) : nil
        return (parts[0], seconds.map { Date(timeIntervalSince1970: $0) })
    }

    // MARK: Writing

    private static let lock = NSLock()
    private static let logger = Logger(subsystem: "de.private.Plattenregal", category: "AppLog")
    private static let directory: URL? = try? FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("Plattenregal/Logs", isDirectory: true)
    private static var runningMarker: URL { directory!.appendingPathComponent(".running") }
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Unit tests run inside the app; they must not fill the real log.
    private static let isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    private static func write(_ level: Level, _ category: String, _ message: String) {
        guard isEnabled else { return }
        switch level {
        case .info: logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning: logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error, .fault: logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        guard let fileURL else { return }
        lock.lock(); defer { lock.unlock() }
        // The log is shared with the real app: a demo's "Alles zurückgesetzt"
        // must never read like one of the own collection.
        let tag = DemoMode.isActive ? "Demo · \(category)" : category
        let line = "\(formatter.string(from: Date()))  \(level.rawValue)  [\(tag)] \(message)\n"
        // O_APPEND: every line lands at the end in one step, also when a second
        // instance writes at the same moment (switching into or out of the
        // demo) – and a failed open never replaces the file.
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        // A long session rotates too, not only a launch.
        var info = stat()
        if fstat(fd, &info) == 0, info.st_size > rotationSize { rotate(fileURL) }
    }

    /// Past this size the file becomes `Plattenregal.old.log` (at launch and
    /// during a session), so the protocol never grows without bounds.
    private static let rotationSize: off_t = 2_000_000

    /// Called with `lock` held. The crash handler's descriptor is pointed at
    /// the new file in one step (`dup2`), so a crash still lands in the
    /// current protocol.
    private static func rotate(_ fileURL: URL) {
        guard let oldFileURL else { return }
        try? FileManager.default.removeItem(at: oldFileURL)
        guard (try? FileManager.default.moveItem(at: fileURL, to: oldFileURL)) != nil else { return }
        let fresh = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fresh >= 0 else { return }
        if crashFD >= 0 { dup2(fresh, crashFD) }
        close(fresh)
    }

    // MARK: Crashes

    /// Swift runtime traps (force unwraps, `fatalError`, failed preconditions –
    /// in Xcode the "breakpoint" stop), invalid memory access and aborts end
    /// the process in a signal. The handler may only use async-signal-safe
    /// calls, so it writes to a file descriptor opened beforehand: the signal
    /// and the raw call stack, then lets the crash continue as usual.
    private static func installCrashHandlers(logPath: String, version: String) {
        crashFD = open(logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        crashFrames = .allocate(capacity: 64)
        let versionBytes = Array(" · Version \(version)".utf8)
        crashVersion = .allocate(capacity: versionBytes.count)
        _ = crashVersion!.initialize(from: versionBytes)
        // A stack overflow (endless recursion) leaves no stack for the
        // handler; it runs on its own one instead (main thread).
        let stackSize = 256 * 1024
        var stack = stack_t(ss_sp: UnsafeMutableRawPointer.allocate(byteCount: stackSize, alignment: 16), ss_size: stackSize, ss_flags: 0)
        sigaltstack(&stack, nil)
        for signal in [SIGTRAP, SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE] {
            var action = sigaction()
            action.__sigaction_u = __sigaction_u(__sa_handler: crashSignalHandler)
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, nil)
        }
        NSSetUncaughtExceptionHandler { exception in
            AppLog.write(.fault, "Absturz", "Nicht abgefangene Ausnahme \(exception.name.rawValue): \(exception.reason ?? "–")\n"
                + exception.callStackSymbols.joined(separator: "\n"))
        }
    }
}

nonisolated(unsafe) private var crashFD: Int32 = -1
/// Allocated up front: the handler must not allocate memory.
nonisolated(unsafe) private var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
/// " · Version 1.0 (7)", prepared at launch for the same reason.
nonisolated(unsafe) private var crashVersion: UnsafeMutableBufferPointer<UInt8>?

nonisolated private func crashSignalHandler(_ signal: Int32) {
    if crashFD >= 0 {
        writeRaw("\n==== ABSTURZ: ")
        switch signal {
        case SIGTRAP: writeRaw("SIGTRAP (Swift-Laufzeitfehler, z. B. erzwungenes Entpacken von nil oder fatalError)")
        case SIGABRT: writeRaw("SIGABRT (abgebrochen)")
        case SIGILL: writeRaw("SIGILL (ungültige Anweisung)")
        case SIGSEGV: writeRaw("SIGSEGV (ungültiger Speicherzugriff)")
        case SIGBUS: writeRaw("SIGBUS (ungültiger Speicherzugriff)")
        case SIGFPE: writeRaw("SIGFPE (Rechenfehler)")
        default: writeRaw("Signal")
        }
        writeRaw(" · Unix-Zeit ")
        writeNumber(Int(time(nil)))
        if let crashVersion { _ = Darwin.write(crashFD, crashVersion.baseAddress, crashVersion.count) }
        writeRaw(" ====\n")
        if let crashFrames {
            let count = backtrace(crashFrames, 64)
            backtrace_symbols_fd(crashFrames, count, crashFD)
        }
        writeRaw("==== Ende Absturz ====\n")
    }
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}

nonisolated private func writeRaw(_ text: StaticString) {
    _ = Darwin.write(crashFD, text.utf8Start, text.utf8CodeUnitCount)
}

nonisolated private func writeNumber(_ value: Int) {
    var digits: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &digits) { buffer in
        var number = max(0, value), index = buffer.count
        repeat {
            index -= 1
            buffer[index] = UInt8(48 + number % 10)
            number /= 10
        } while number > 0 && index > 0
        _ = Darwin.write(crashFD, buffer.baseAddress! + index, buffer.count - index)
    }
}

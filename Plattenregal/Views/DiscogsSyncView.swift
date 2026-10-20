import SwiftUI

/// Two lines at most: what is happening overall (with animated dots and a
/// small "x" to cancel), and underneath the current step — collection,
/// wantlist, then the tracklists. Reports "abgeschlossen" only when the
/// tracklist download after the sync is through as well.
struct DiscogsSyncStatusView: View {
    @State private var sync = DiscogsSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            HStack(spacing: AppStyle.itemSpacing) {
                if sync.isRunning {
                    ActivityRing(size: 13)
                    Text("Synchronisierung läuft")
                    CancelIconButton(help: String(localized: "Synchronisierung abbrechen"), keys: "⌘.") { sync.cancel() }
                } else {
                    Text(sync.status)
                        .transition(.opacity)
                    if let error = sync.error {
                        ErrorInfoButton(title: sync.status, message: error) { sync.dismissStatus() }
                    }
                }
            }
            if let detail {
                // Step on the second line, its counter on the third.
                // Gentle motion: steps blend into each other, counters roll,
                // and the counter line eases in and out instead of popping.
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text(detail.text)
                        .foregroundStyle(detail.isError ? AnyShapeStyle(AppStyle.errorColor) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                        .contentTransition(.interpolate)
                    if let progress = detail.progress {
                        Text(progress)
                            .foregroundStyle(.tertiary).lineLimit(1)
                            .contentTransition(.numericText())
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .textSelection(.enabled)
                .transition(.opacity)
            }
        }
        .animation(AppStyle.statusAnimation, value: sync.isRunning)
        .animation(AppStyle.statusAnimation, value: detail?.text)
        .animation(AppStyle.progressAnimation, value: detail?.progress)
    }

    private var detail: (text: String, progress: String?, isError: Bool)? {
        if sync.busy { return (sync.status, nil, false) }
        if sync.isRunning {
            let progress = sync.tracklistProgress.map { progress in
                // Zero-padded to the total's width, so the counter doesn't jump around.
                let digits = String(progress.total).count
                return String(localized: "\(String(format: "%0\(digits)d", progress.done)) von \(progress.total)", comment: "Fortschritt beim Laden der Tracklisten")
            }
            return (String(localized: "Tracklisten werden geladen"), progress, false)
        }
        // Errors live in the "i" popover, not in the line.
        if let summary = sync.summary { return (summary, nil, false) }
        return nil
    }
}

/// Small "i" next to a failed sync; opens a glass popover (like the record
/// popover) with the error in plain words and a way to dismiss the hint.
private struct ErrorInfoButton: View {
    let title: String
    let message: String
    let dismiss: () -> Void
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppStyle.warningColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Was ist passiert?")
        .accessibilityLabel("Fehlerdetails anzeigen")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                Label(title.isEmpty ? String(localized: "Hinweis") : title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(AppStyle.warningColor)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Hinweis ausblenden") { showing = false; dismiss() }
                        .appLinkButton().font(.callout)
                }
            }
            .padding(AppStyle.cardPadding)
            .frame(width: 320)
            .appPopoverSurface()
        }
    }
}

/// The sync as a floating Liquid Glass capsule at the top of the page, right
/// where the pull-to-refresh ring filled up: the ring spins while Discogs is
/// read, fills with the tracklist count, turns into a checkmark with the
/// summary and slides away. Each step stays a moment before the next one
/// takes over (quick ones in between are skipped), and every change — text,
/// icon, size — moves in one animation, so the capsule glides instead of jumping.
struct DiscogsSyncPill: View {
    @State private var sync = DiscogsSyncService.shared
    /// What the capsule shows; follows `current` (see `follow`).
    @State private var shown: Content?
    @State private var shownSince = ContinuousClock.now
    @State private var pendingStep: Task<Void, Never>?

    private enum Phase: Equatable { case loading, tracklists, done, failed, note }
    private struct Content: Equatable {
        var phase: Phase
        var title: String
        var subtitle: String?
        var progress: Double?
        var error: String?
        var isRunning: Bool { phase == .loading || phase == .tracklists }
        /// Only the numbers moved: shown right away.
        func isSameStep(as other: Content) -> Bool { phase == other.phase && title == other.title }
    }

    /// How long a step stays before the next one replaces it.
    private static let minimumStep: Duration = .milliseconds(900)
    private static let entrance = Animation.spring(duration: 0.5, bounce: 0.2)

    private var current: Content? {
        guard sync.hasStatus else { return nil }
        let phase: Phase =
            if sync.busy { .loading }
            else if sync.isRunning { .tracklists }
            else if sync.error != nil { .failed }
            else if sync.summary != nil || sync.status == DiscogsSyncService.completedStatus { .done }
            else { .note }
        let title = switch phase {
        case .loading: sync.status.isEmpty ? String(localized: "Synchronisierung läuft") : sync.status
        case .tracklists: String(localized: "Tracklisten werden geladen")
        case .done: String(localized: "Synchronisiert")
        case .failed: sync.status.isEmpty ? String(localized: "Synchronisierung nicht möglich") : sync.status
        case .note: sync.status.isEmpty ? String(localized: "Hinweis") : sync.status
        }
        let subtitle: String? = switch phase {
        case .tracklists: sync.tracklistProgress.map { String(localized: "\($0.done.formatted()) von \($0.total.formatted())") }
        case .done: sync.summary
        default: nil
        }
        let progress = phase == .tracklists ? sync.tracklistProgress.map { Double($0.done) / Double(max(1, $0.total)) } : nil
        return Content(phase: phase, title: title, subtitle: subtitle, progress: progress, error: sync.error)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let shown {
                pill(shown)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
        }
        .onAppear { shown = current; shownSince = .now }
        .onChange(of: current) { _, new in follow(new) }
        .onDisappear { pendingStep?.cancel() }
    }

    /// Numbers within a step update at once; a new step (or the end) waits
    /// until the current one has been visible for `minimumStep`, and only the
    /// latest state is shown then.
    private func follow(_ new: Content?) {
        pendingStep?.cancel()
        if let old = shown, let new, old.isSameStep(as: new) {
            withAnimation(AppStyle.statusAnimation) { shown = new }
            return
        }
        let wait = shown == nil ? .zero : Self.minimumStep - (ContinuousClock.now - shownSince)
        pendingStep = Task {
            if wait > .zero {
                do { try await Task.sleep(for: wait) } catch { return }
            }
            withAnimation(shown == nil || new == nil ? Self.entrance : AppStyle.statusAnimation) { shown = new }
            shownSince = .now
        }
    }

    private func pill(_ content: Content) -> some View {
        HStack(spacing: AppStyle.itemSpacing) {
            icon(content)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .id(content.isRunning ? Phase.loading : content.phase)
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(content.title)
                    .font(.callout)
                    .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                if let subtitle = content.subtitle {
                    // In the accent like the ring and the checkmark (Klassisch: petrol), not grey.
                    Text(subtitle)
                        .font(.caption.weight(.medium)).foregroundStyle(AppStyle.accent)
                        .monospacedDigit().lineLimit(1)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            if content.isRunning {
                CancelIconButton(help: String(localized: "Synchronisierung abbrechen"), keys: "⌘.") { sync.cancel() }
                    .transition(.opacity)
            } else if let error = content.error {
                ErrorInfoButton(title: content.title, message: error) { sync.dismissStatus() }
                    .transition(.opacity)
            } else if content.phase == .note {
                CancelIconButton(help: String(localized: "Ausblenden")) { sync.dismissStatus() }
                    .transition(.opacity)
            }
        }
        // Text and icon move with the capsule as one piece while it resizes.
        .geometryGroup()
        .activityPillChrome()
    }

    @ViewBuilder private func icon(_ content: Content) -> some View {
        switch content.phase {
        case .loading:
            ActivityRing()
        case .tracklists:
            ActivityRing(progress: content.progress)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppStyle.accent)
                .symbolEffect(.bounce, value: content.phase)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppStyle.warningColor)
        case .note:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// The small "x" used to cancel a running sync.
private struct CancelIconButton: View {
    let help: String
    var keys: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(keys.map { AppShortcuts.help(help, keys: $0) } ?? help)
        .accessibilityLabel(help)
    }
}

import SwiftUI

/// The short tour through the app: a few pages with two pictures of the
/// real app, fanned out, and a few sentences each. Opens by itself on the first launch (not in
/// the demo) and from Hilfe › „Tour durch Plattenregal …“ at any time.
///
/// The pictures are screenshots of the demo, in German and English, light
/// and dark (Assets.xcassets/Tour). `Scripts/tour-screenshots.sh` takes them
/// again after the pages changed.
@MainActor @Observable
final class AppTour {
    static let shared = AppTour()
    /// Set once the tour was closed, however; "Einstellungen zurücksetzen" brings it back.
    static let seenKey = "tourSeen"

    /// The open tour; a new one per opening, so it starts on the first page.
    var request: TourRequest?

    func show() { request = TourRequest() }

    /// On the first launch only. Not in the demo (its settings are fresh on
    /// every start) and not for the tests, which run inside the app.
    func showOnFirstLaunch() {
        #if DEBUG
        // To look at the tour in the demo: --preview-tour.
        if ProcessInfo.processInfo.arguments.contains("--preview-tour") { return show() }
        #endif
        guard !DemoMode.isActive, !AppDefaults.store.bool(forKey: Self.seenKey),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        show()
    }

    func markSeen() { AppDefaults.store.set(true, forKey: Self.seenKey) }
}

struct TourRequest: Identifiable { let id = UUID() }

/// Hilfe › „Tour durch Plattenregal …“, in place of the help book the app doesn't have.
struct TourCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Tour durch Plattenregal …") {
            // The main window may be closed (the app keeps running without it).
            openWindow(id: "main")
            AppTour.shared.show()
        }
    }
}

struct TourPage: Identifiable {
    let id: Int
    let title: String
    let text: String
    /// Two names in Assets.xcassets/Tour, without language: the one behind, then the one in front.
    let images: [String]
    /// Discogs page: a way straight to the token.
    var opensDiscogsSettings = false

    static let all: [TourPage] = [
        TourPage(id: 0, title: String(localized: "Willkommen bei Plattenregal"),
                 text: String(localized: "Deine Schallplatten auf dem Mac – die ganze Sammlung auf einen Blick, dein Regal zu Hause als Abbild und immer die Antwort auf die Frage, wo eine Platte steht."),
                 images: ["collection", "wantlist"]),
        TourPage(id: 1, title: String(localized: "Alles kommt von Discogs"),
                 text: String(localized: "Plattenregal zeigt deine Discogs-Collection und -Wantlist. Trag einmal deinen persönlichen Token ein, dann holt ⌥⌘R alle Platten. Neue Platten trägst du bei Discogs ein – beim nächsten Abgleich sind sie hier."),
                 images: ["account", "sync"], opensDiscogsSettings: true),
        TourPage(id: 2, title: String(localized: "Dein Regal, Fach für Fach"),
                 text: String(localized: "Die Regal-Seite zeigt deine Regale so, wie sie bei dir stehen, mit dem Buchstabenbereich und der Anzahl Platten jedes Fachs. Für jede Platte siehst du, wo sie hingehört: Fach, Position und zwischen welchen beiden Platten."),
                 images: ["rack", "table"]),
        TourPage(id: 3, title: String(localized: "Neue Platten einsortieren"),
                 text: String(localized: "Das + an einem Fach listet alle Platten, die noch keinen Platz haben. Ein Klick stellt eine Platte an ihre alphabetische Stelle; gehört sie in ein anderes Fach, führt dich der Pfeil dorthin."),
                 images: ["add", "place"]),
        TourPage(id: 4, title: String(localized: "Statistik und Wertentwicklung"),
                 text: String(localized: "Was steckt in deiner Sammlung? Künstler, Styles, Jahrzehnte und Labels – und der Wert laut Discogs-Marktplatz, mit jedem Abgleich als Verlauf."),
                 images: ["value", "facts"]),
        TourPage(id: 5, title: String(localized: "Export und Sicherung"),
                 text: String(localized: "Collection und Wantlist gehen als CSV oder PDF hinaus, auf Wunsch regelmäßig von selbst. Wo deine Platten im Regal stehen, gibt es nur hier – Plattenregal sichert es automatisch."),
                 images: ["export", "backup"]),
    ]
}

struct TourView: View {
    let close: () -> Void
    @State private var index = 0
    /// Direction of the last step, for the slide.
    @State private var forward = true
    @Environment(\.openSettings) private var openSettings

    private let pages = TourPage.all
    private var page: TourPage { pages[index] }
    private var isLast: Bool { index == pages.count - 1 }

    static let width: CGFloat = 620
    static let pictureHeight: CGFloat = 290

    var body: some View {
        VStack(spacing: 0) {
            TourPageContent(page: page)
                .id(page.id)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            controls
                .padding(.top, AppStyle.sectionSpacing)
        }
        .padding(AppStyle.pagePadding)
        .frame(width: Self.width)
        .clipped()
    }

    /// A short push in the direction of the step; only a fade with "Bewegung reduzieren".
    private var pageTransition: AnyTransition {
        AppStyle.reduceMotion ? .opacity
            : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                          removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            HStack(spacing: AppStyle.itemSpacing) {
                if !isLast {
                    GhostButton(title: String(localized: "Überspringen"), action: close)
                }
                // Not in the demo: Discogs is switched off there.
                if page.opensDiscogsSettings && !DemoMode.isActive {
                    GhostButton(title: String(localized: "Token eintragen …"), action: openDiscogsSettings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            dots
            HStack(spacing: AppStyle.itemSpacing) {
                if index > 0 {
                    SecondaryButton(title: String(localized: "Zurück")) { go(to: index - 1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                PrimaryButton(title: isLast ? String(localized: "Los geht’s") : String(localized: "Weiter")) {
                    if isLast { close() } else { go(to: index + 1) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // → as well as Return.
        .background {
            Button("Weiter") { if !isLast { go(to: index + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var dots: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            ForEach(pages) { item in
                Button { go(to: item.id) } label: {
                    Circle()
                        .fill(item.id == index ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(Color.primary.opacity(0.2)))
                        .frame(width: 7, height: 7)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
    }

    private func go(to target: Int) {
        guard target != index, pages.indices.contains(target) else { return }
        forward = target > index
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { index = target }
    }

    /// The Discogs page leads straight to the token.
    private func openDiscogsSettings() {
        close()
        SettingsRequest.shared.show(.discogs)
        openSettings()
    }

    private struct TourPageContent: View {
        let page: TourPage
        var body: some View {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                TourPicture(names: page.images)
                    .frame(maxWidth: .infinity)
                    .frame(height: TourView.pictureHeight)
                    .padding(.bottom, AppStyle.itemSpacing)
                Text(page.title).font(AppStyle.dialogTitle)
                Text(page.text)
                    .font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Up to three lines in German and English; the same height on every page.
                    .frame(minHeight: 66, alignment: .topLeading)
            }
        }
    }
}

/// Two cut-outs of the app, fanned out: one up left, one down right in front
/// of it. Light and dark come from the asset catalog; the language is the app's.
private struct TourPicture: View {
    let names: [String]

    /// Cut off in the middle of a panel, list or page: they end in a fade
    /// there, not an edge.
    private static let cutBelow: Set<String> = ["add", "backup"]
    private static let cutRight: Set<String> = ["collection", "wantlist", "rack", "table", "place", "value", "facts"]

    private static let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "de"

    var body: some View {
        ZStack {
            ForEach(Array(names.enumerated()), id: \.offset) { position, name in
                let behind = position == 0
                picture(name)
                    .frame(maxWidth: 400, maxHeight: 210)
                    .offset(x: behind ? -70 : 70, y: behind ? -40 : 40)
            }
        }
    }

    private func picture(_ name: String) -> some View {
        Image("Tour/\(name)-\(Self.language)")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.cardRadius).strokeBorder(AppStyle.borderColor)
            }
            // Edge and shadow fade out with the picture.
            .mask { fade(to: .bottom, from: Self.cutBelow.contains(name) ? 0.7 : 1) }
            .mask { fade(to: .trailing, from: Self.cutRight.contains(name) ? 0.8 : 1) }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .accessibilityHidden(true)
    }

    /// Opaque up to `start` (0…1), then fading out towards `edge`.
    private func fade(to edge: UnitPoint, from start: CGFloat) -> some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: start), .init(color: .clear, location: 1)],
                       startPoint: edge == .bottom ? .top : .leading, endPoint: edge)
    }
}

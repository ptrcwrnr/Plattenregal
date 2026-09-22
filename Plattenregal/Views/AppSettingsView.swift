import SwiftUI
import SwiftData

struct AppSettingsView: View {
    var body: some View {
        TabView {
            ShelfSettingsView().tabItem { Label("Regal", systemImage: "square.grid.3x3") }
            DiscogsSettingsView().tabItem { Label("Discogs", systemImage: "opticaldisc") }
            AppearanceSettingsView().tabItem { Label("Darstellung", systemImage: "paintbrush") }
        }.frame(width: 650, height: 570)
    }
}
struct ShelfSettingsView: View {
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @State private var editing: Shelf?
    var body: some View {
        Form {
            Section("KALLAX") { LabeledContent("Reihen", value: String(ShelfGeometry.rows)); LabeledContent("Spalten", value: String(ShelfGeometry.columns)) }
            Section("Kapazität, Namen und Infotexte") {
                ForEach(shelves) { shelf in
                    HStack {
                        Text(shelf.title); Spacer(); Text("\(shelf.copies.count) / \(shelf.capacity)").foregroundStyle(.secondary)
                        Button("Bearbeiten") { editing = shelf }
                    }
                }
            }
        }.formStyle(.grouped).sheet(item: $editing) { ShelfEditor(shelf: $0) }
    }
}
struct DiscogsSettingsView: View {
    @State private var model = DiscogsSettingsModel()
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Persönlicher API-Token") {
                SecureField("Discogs-Token", text: $model.token)
                Text("Der Token wird ausschließlich im macOS-Schlüsselbund gespeichert. Ein leeres Feld beim Speichern entfernt den Token.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecondaryButton(title: "Token speichern") { model.save() }.disabled(model.busy || DiscogsSyncService.shared.busy)
                    PrimaryButton(title: "Speichern & Verbindung testen") { Task { await model.test() } }.disabled(model.busy || DiscogsSyncService.shared.busy)
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if !model.status.isEmpty { Text(model.status).foregroundStyle(model.failed ? AppStyle.errorColor : .secondary) }
                Link("Token bei Discogs erstellen ↗", destination: URL(string: "https://www.discogs.com/settings/developers")!)
            }
            DiscogsSyncView()
            Section("Daten und Attribution") {
                Text("API-Daten werden nach spätestens sechs Stunden vor der Anzeige aktualisiert. Cover werden nur vorübergehend im Arbeitsspeicher gepuffert. Bei fehlender Verbindung bleiben eigene Exemplar- und Standortdaten verfügbar.")
                Text("This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.").font(.caption)
                Link("Aktuelle Discogs API-Nutzungsbedingungen ↗", destination: URL(string: "https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use")!)
            }
        }.formStyle(.grouped)
        .onAppear { model.load() }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("collectionLayout") private var layout = "grid"
    @AppStorage("coverSize") private var coverSize = 155.0
    var body: some View {
        Form {
            Picker("Bevorzugte Darstellung", selection: $layout) { Text("Cover").tag("grid"); Text("Liste").tag("list") }
            Slider(value: $coverSize, in: 120...220, step: 5) { Text("Covergröße") }
            Text("\(Int(coverSize)) Punkte").foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

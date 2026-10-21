import SwiftUI

// MARK: - Apple TV

/// Pairing with Plattenregal on Apple TV and what it gets from here.
struct AppleTVSettingsView: View {
    @State private var link = AppleTVLink.shared
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        @Bindable var link = link
        SettingsPage {
            SettingsCard(title: String(localized: "Apple TV"),
                         subtitle: String(localized: "Plattenregal für Apple TV zeigt Collection, Wantlist, Statistik und das Regal auf dem Fernseher. Discogs-Token und Belegung holt es von hier – im Heimnetz und verschlüsselt, solange Plattenregal am Mac geöffnet ist.")) {
                if DemoMode.isActive {
                    SettingsNote(String(localized: "In der Demo ist die Verbindung zum Apple TV aus – die Beispielsammlung soll nicht auf deinen Fernseher."))
                } else {
                    pairingContent
                    if let error = link.listenerError {
                        AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition())
                    }
                    Divider()
                    if link.devices.isEmpty {
                        SettingsNote(String(localized: "Noch kein Apple TV verbunden."))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(link.devices.enumerated()), id: \.element.id) { index, device in
                                if index > 0 { Divider() }
                                deviceRow(device).padding(.vertical, AppStyle.tightSpacing)
                            }
                        }
                    }
                }
            }
            .animation(AppStyle.standardAnimation, value: link.pairing)
            // A pairing left open would keep accepting any Apple TV that asks.
            .onDisappear { link.closePairing() }

            SettingsCard(title: String(localized: "Was das Apple TV bekommt")) {
                SettingsRow(title: String(localized: "Discogs-Token mitschicken"),
                            hint: String(localized: "Dann gleicht das Apple TV selbst mit Discogs ab. Ohne Token muss er dort von Hand eingetragen werden.")) {
                    Toggle("Discogs-Token mitschicken", isOn: $link.sendsToken).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsNote(String(localized: "Die Belegung geht immer mit – dieselben Angaben wie in einer Sicherung: Regale, Fächer, Sperren und der Platz jeder Platte. Das Apple TV holt sie beim Start und alle paar Minuten und ändert selbst nichts daran."))
            }
        }
    }

    // MARK: Pairing

    @ViewBuilder private var pairingContent: some View {
        switch link.pairing {
        case nil:
            SettingsRow(title: String(localized: "Neues Apple TV"),
                        hint: String(localized: "Auf dem Apple TV: Plattenregal öffnen, dann Einstellungen → „Mit Mac verbinden …“.")) {
                PrimaryButton(title: String(localized: "Apple TV verbinden …")) { link.startPairing() }
            }
        case .waiting:
            HStack(spacing: AppStyle.rowSpacing) {
                ActivityRing(size: 14)
                Text("Öffne auf dem Apple TV Plattenregal → Einstellungen → „Mit Mac verbinden …“ und wähle „\(AppleTVLink.macName)“.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppStyle.rowSpacing)
                GhostButton(title: String(localized: "Abbrechen")) { link.cancelPairing() }
            }
        case let .code(device, error):
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                Text("„\(device)“ möchte sich verbinden. Gib den Code ein, den der Fernseher zeigt:")
                HStack(spacing: AppStyle.itemSpacing) {
                    GlassTextField(placeholder: String(localized: "Sechsstelliger Code"), text: $code,
                                   onSubmit: submit, focus: $codeFocused)
                        .frame(width: 220)
                        .onAppear { codeFocused = true }
                    PrimaryButton(title: String(localized: "Verbinden"), action: submit)
                        .disabled(code.filter(\.isNumber).count != 6)
                    Spacer()
                    GhostButton(title: String(localized: "Abbrechen")) { link.cancelPairing() }
                }
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }
        case .checking:
            HStack(spacing: AppStyle.rowSpacing) {
                ActivityRing(size: 14)
                Text("Prüfe den Code …")
            }
        case .done(let device):
            HStack(spacing: AppStyle.rowSpacing) {
                AppBanner(message: String(localized: "„\(device)“ ist verbunden und holt sich jetzt Token und Regal."), kind: .success)
                PrimaryButton(title: String(localized: "Fertig")) { link.finishPairing() }
            }
        case .failed(let message):
            HStack(spacing: AppStyle.rowSpacing) {
                AppBanner(message: message, kind: .error)
                SecondaryButton(title: String(localized: "Noch einmal")) { link.startPairing() }
            }
        }
    }

    private func submit() {
        guard code.filter(\.isNumber).count == 6 else { return }
        link.submit(code: code)
        code = ""
    }

    private func deviceRow(_ device: AppleTVLink.Device) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(device.name)
                Text(device.lastFetch.map { String(localized: "Zuletzt abgeholt \($0.formatted(.relative(presentation: .named)))") }
                     ?? String(localized: "Verbunden am \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            GhostButton(title: String(localized: "Entfernen")) { link.remove(device) }
        }
    }
}

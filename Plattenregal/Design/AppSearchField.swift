import SwiftUI

/// One search field for the whole app, inside the bar of the page switch
/// in the toolbar (see `ToolbarSearchField`) instead of a capsule of its own:
/// a magnifying glass that opens into a text field with its own placeholder,
/// clear button and Esc. Closed it is only the glass, as wide as an option
/// of the switch beside it; open it is `toolbarSearchWidth` wide. The caller
/// opens and closes it in `AppStyle.searchOpenAnimation` and
/// `searchCloseAnimation`, so the bar around it follows in the same spring;
/// the glass bounces once on opening.
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// Focus of the text field (⌘F).
    let focus: FocusState<Bool>.Binding
    /// Open: the text field beside the glass; closed only the glass.
    let open: Bool
    /// A click on the glass: opens the field, or focuses it when open.
    let onOpen: () -> Void
    /// Counts the openings, for the bounce of the glass (not on closing).
    @State private var openings = 0

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppStyle.toolbarLabel)
                    .symbolEffect(.bounce, options: .nonRepeating, value: openings)
                    .padding(.leading, AppStyle.rowSpacing)
                    .padding(.trailing, open ? AppStyle.itemSpacing : AppStyle.rowSpacing)
                    .frame(height: AppStyle.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AppShortcuts.help(String(localized: "Suchen"), keys: "⌘F"))
            .accessibilityLabel(String(localized: "Suchen"))
            if open {
                field
                    .padding(.trailing, AppStyle.rowSpacing)
                    .transition(.opacity)
            }
        }
        .frame(width: open ? AppStyle.toolbarSearchWidth : nil, alignment: .leading)
        .clipped()
        .onChange(of: open) { _, new in
            if new && !AppStyle.reduceMotion { openings += 1 }
        }
    }

    private var field: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            TextField(placeholder, text: $text, prompt: Text(verbatim: ""))
                .textFieldStyle(.plain).noTextAutoFill()
                // Its own placeholder instead of the field's: the field swaps
                // its prompt at once, this one fades to a new text in the beat
                // of a page switch ("Collection durchsuchen" → "Regal
                // durchsuchen"). Gone at once on the first key.
                .background(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Text(placeholder)
                            .foregroundStyle(.placeholder)
                            .lineLimit(1)
                            .id(placeholder)
                            .transition(AppStyle.pageFadeTransition)
                    }
                    .opacity(text.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .focused(focus)
                // Esc clears the query; with an empty field it gives up the focus.
                .onKeyPress(.escape) {
                    if !text.isEmpty { text = ""; return .handled }
                    focus.wrappedValue = false
                    return .handled
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Suche löschen"))
                .accessibilityLabel(String(localized: "Suche löschen"))
            }
        }
    }
}

/// A text field in the same Liquid Glass capsule as the search bars, for
/// names and the like – no gray box, no magnifying glass.
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: (() -> Void)?
    var focus: FocusState<Bool>.Binding?
    var body: some View {
        focusable(field.textFieldStyle(.plain))
            .onSubmit { onSubmit?() }
            .searchBarChrome()
    }
    @ViewBuilder private var field: some View {
        if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text).noTextAutoFill() }
    }
    @ViewBuilder private func focusable(_ field: some View) -> some View {
        if let focus { field.focused(focus) } else { field }
    }
}

/// ⌘F presses, counted, and whether the search field in the toolbar has the
/// focus. One object for the window, handed to every page (see `PageStack`):
/// the field answers each request by taking the focus (see
/// `ToolbarSearchField`); pages ask whether typing goes into it (the shelf's
/// ⌘Z, for example, belongs to the field's text then).
@Observable final class SearchRequests {
    private(set) var count = 0
    var fieldFocused = false
    func request() { count += 1 }
}

private struct SearchRequestsKey: EnvironmentKey {
    static let defaultValue: SearchRequests? = nil
}
extension EnvironmentValues {
    var searchRequests: SearchRequests? {
        get { self[SearchRequestsKey.self] }
        set { self[SearchRequestsKey.self] = newValue }
    }
}

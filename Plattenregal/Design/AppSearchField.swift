import SwiftUI

/// One search field for the whole app: icon, text field, clear button in a
/// Liquid Glass capsule (same look as the search on the shelf page).
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// Focus of the text field, for the search field in the toolbar (⌘F).
    let focus: FocusState<Bool>.Binding
    /// Sits on the window's toolbar (see `searchBarChrome(onToolbar:)`).
    var onToolbar = false
    var body: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).noTextAutoFill()
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
        .searchBarChrome(onToolbar: onToolbar)
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

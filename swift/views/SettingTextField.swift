import SwiftUI

/// A text field for one string setting core owns.
///
/// Core trims and validates what it stores, so a field bound straight to
/// `appSettings` would rewrite the text under the cursor — a trailing space
/// gone mid-word, a half-typed URL refused and replaced. The field edits a
/// draft of its own, sends it when typing pauses, when focus leaves and when
/// the screen goes away, and takes core's value only while nobody is typing.
struct SettingTextField: View {
    let title: String
    /// What core has stored.
    let value: String
    let commit: (String) -> Void
    @State private var draft: String?
    @FocusState private var isFocused: Bool

    private var text: String { draft ?? value }

    var body: some View {
        TextField(title, text: Binding(get: { text }, set: { draft = $0 }))
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if !focused { send() }
            }
            .onDisappear { send() }
            .task(id: draft) {
                guard draft != nil else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                send()
            }
    }

    private func send() {
        guard let draft else { return }
        if draft != value { commit(draft) }
        // Keep the draft while the field is being edited; core's answer is the
        // text once it is not.
        if !isFocused { self.draft = nil }
    }
}

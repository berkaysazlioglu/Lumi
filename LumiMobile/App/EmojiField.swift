import SwiftUI
import UIKit

/// A field that opens straight on the emoji keyboard (Edit Project…, decision
/// 133) — iOS has no public emoji picker; asking for the `emoji` input mode
/// is the system's own way in. Each pick replaces the previous one, so the
/// field always holds the last emoji chosen.
struct EmojiField: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.font = font
        field.textAlignment = .center
        field.tintColor = .clear
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Switching the icon to Emoji opens the keyboard right away.
        if text.isEmpty { DispatchQueue.main.async { field.becomeFirstResponder() } }
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) {
            // Keep only the newest character: picking again swaps the emoji.
            let last = field.text?.last.map(String.init) ?? ""
            if field.text != last { field.text = last }
            text.wrappedValue = last
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
        }
    }
}

final class EmojiTextField: UITextField {
    /// The emoji keyboard when the user has it enabled (it is by default);
    /// otherwise the regular one, from which the globe still reaches it.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

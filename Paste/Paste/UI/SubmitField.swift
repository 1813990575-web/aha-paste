import AppKit
import SwiftUI

struct SubmitField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    var fontSize: CGFloat = 14
    var focusRequestID: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placeholder: placeholder, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = SubmitTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.isBordered = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.delegate = context.coordinator
        field.onSubmit = onSubmit
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.font = .systemFont(ofSize: fontSize, weight: .medium)
        context.coordinator.text = $text
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        let placeholder: String
        let onSubmit: () -> Void
        var lastFocusRequestID = -1

        init(text: Binding<String>, placeholder: String, onSubmit: @escaping () -> Void) {
            self.text = text
            self.placeholder = placeholder
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            text.wrappedValue = field.stringValue
        }
    }
}

private final class SubmitTextField: NSTextField {
    var onSubmit: (() -> Void)?

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if let movement = notification.userInfo?["NSTextMovement"] as? Int,
           movement == NSReturnTextMovement {
            onSubmit?()
        }
    }
}

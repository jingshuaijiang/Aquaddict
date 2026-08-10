import SwiftUI
import ContactsUI

// System contact picker (out-of-process — no permission prompt needed).
// Multi-select; returns display names.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: ([String]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        init(onPick: @escaping ([String]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController,
                           didSelect contacts: [CNContact]) {
            onPick(contacts.compactMap {
                CNContactFormatter.string(from: $0, style: .fullName)
            })
        }

        func contactPicker(_ picker: CNContactPickerViewController,
                           didSelect contact: CNContact) {
            onPick([CNContactFormatter.string(from: contact, style: .fullName)]
                .compactMap { $0 })
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onPick([])
        }
    }
}

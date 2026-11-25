import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

/// 系统文件选择器（UIDocumentPickerViewController 包装）。
/// 比 SwiftUI 的 fileImporter 可靠，`asCopy: true` 会先把文件复制进 App 沙盒，
/// 省掉 security-scoped 授权，iOS 16 上也不会出现“点了没反应”。
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.item]
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes,
                                                    asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
#endif

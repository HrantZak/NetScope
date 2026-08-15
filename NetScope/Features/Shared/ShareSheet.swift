import SwiftUI
import UIKit

/// `URL` wrapper so a file can drive `.sheet(item:)`.
struct ExportedFile: Identifiable, Hashable {
    var url: URL
    var id: String { url.absoluteString }
}

/// Minimal `UIActivityViewController` bridge for sharing an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

import SwiftUI
import UIKit

/// Charge utile partageable (identifiable pour `.sheet(item:)`).
struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Pont SwiftUI vers `UIActivityViewController` (feuille de partage système).
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

import SwiftUI
import UIKit

/// Wraps UIActivityViewController for SwiftUI sheets.
/// Relocated from StatsView.swift (deleted in WO-8); consumed by SettingsTabView's data export.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import UIKit

/// Thin wrapper over `UIFeedbackGenerator`.
///
/// Generators are created lazily and kept alive so the Taptic Engine stays
/// warm; creating one per tap adds latency to the very feedback it produces.
@MainActor
enum Haptics {

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepare() {
        selectionGenerator.prepare()
        impactLight.prepare()
        impactMedium.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }

    static func light() {
        impactLight.impactOccurred()
    }

    static func medium() {
        impactMedium.impactOccurred()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
    }
}

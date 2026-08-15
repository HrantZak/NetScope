import Foundation
import UserNotifications

/// Local notifications for network changes.
///
/// Local only — no push server, no account, nothing paid. Permission is asked
/// for lazily, the first time a notification would actually be useful.
actor NotificationService {

    private var hasRequestedAuthorization = false
    private var isAuthorized = false

    /// Asks for permission once per launch, caching the answer.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        if hasRequestedAuthorization { return isAuthorized }
        hasRequestedAuthorization = true

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            isAuthorized = false
        }

        return isAuthorized
    }

    /// Posts a notification about a network event.
    func notify(title: String, body: String, identifier: String = UUID().uuidString) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Summarises a batch of changes in one notification rather than spamming
    /// one per device.
    func notifyDeviceChanges(appeared: [Device], disappeared: [Device], networkName: String) async {
        guard !appeared.isEmpty || !disappeared.isEmpty else { return }

        var parts: [String] = []
        if !appeared.isEmpty {
            let names = appeared.prefix(3).map(\.displayName).joined(separator: ", ")
            let extra = appeared.count > 3 ? " +\(appeared.count - 3) more" : ""
            parts.append("New: \(names)\(extra)")
        }
        if !disappeared.isEmpty {
            let names = disappeared.prefix(3).map(\.displayName).joined(separator: ", ")
            let extra = disappeared.count > 3 ? " +\(disappeared.count - 3) more" : ""
            parts.append("Left: \(names)\(extra)")
        }

        await notify(
            title: networkName.isEmpty ? "Network changed" : networkName,
            body: parts.joined(separator: "\n")
        )
    }
}

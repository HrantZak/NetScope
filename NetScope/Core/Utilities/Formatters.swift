import Foundation

/// Shared formatters. `DateFormatter` and friends are expensive to build, so
/// they are created once and reused.
///
/// The formatters are marked `nonisolated(unsafe)` because Foundation's date
/// formatters are not `Sendable`. Reading from them is documented as thread
/// safe as long as they are never reconfigured, which is exactly how they are
/// used here: fully set up inside the initialiser and never mutated again.
enum Formatters {

    nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// "just now", "5m ago", "3d ago".
    static func relativeString(from date: Date, reference: Date = .now) -> String {
        let interval = reference.timeIntervalSince(date)
        if interval < 45 { return "just now" }
        return relative.localizedString(for: date, relativeTo: reference)
    }

    /// "1.4 s", "820 ms" — used for scan durations.
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes)m \(remainder)s"
    }

    static func latency(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "—" }
        if milliseconds < 1 { return "<1 ms" }
        return String(format: milliseconds < 10 ? "%.1f ms" : "%.0f ms", milliseconds)
    }

    /// Formats a MAC for display, or explains why it is missing.
    static func macDescription(_ mac: String?) -> String? {
        guard let mac else { return nil }
        return mac.uppercased()
    }
}

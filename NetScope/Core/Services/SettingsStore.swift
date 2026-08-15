import Foundation
import Observation

/// Persisted user settings.
///
/// `UserDefaults` is the right tool here: these are small, read at launch and
/// written rarely. Scan results live in `FileStore` instead.
///
/// Persistence is wired through `withObservationTracking` rather than `didSet`,
/// which the `@Observable` macro does not support on its stored properties. One
/// observation covers every setting and re-arms itself after each write.
@MainActor
@Observable
final class SettingsStore {

    private enum Key {
        static let configuration = "scan.configuration"
        static let browse = "browse.preferences"
        static let hasSeenWelcome = "app.hasSeenWelcome"
        static let appearance = "app.appearance"
    }

    enum AppearanceMode: String, CaseIterable, Identifiable, Sendable, Codable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var symbolName: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }
    }

    var configuration: ScanConfiguration
    var browse: BrowsePreferences
    var appearance: AppearanceMode
    var hasSeenWelcome: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configuration = Self.decode(ScanConfiguration.self, from: defaults, key: Key.configuration) ?? .default
        self.browse = Self.decode(BrowsePreferences.self, from: defaults, key: Key.browse) ?? .default
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)

        observeChanges()
    }

    func resetScanSettings() {
        configuration = .default
    }

    func resetLayout() {
        browse = .default
    }

    // MARK: - Persistence

    /// Watches every setting once; `onChange` fires *before* the new value is
    /// stored, so the write is deferred to the next main-actor turn and the
    /// observation is then re-armed for the following change.
    private func observeChanges() {
        withObservationTracking {
            _ = configuration
            _ = browse
            _ = appearance
            _ = hasSeenWelcome
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.persist()
                self.observeChanges()
            }
        }
    }

    private func persist() {
        write(configuration, forKey: Key.configuration)
        write(browse, forKey: Key.browse)
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome)
    }

    private func write<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from defaults: UserDefaults,
        key: String
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}

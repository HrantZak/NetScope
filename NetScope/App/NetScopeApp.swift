import SwiftUI

@main
struct NetScopeApp: App {

    @State private var appEnvironment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.settings.appearance.colorScheme)
                .tint(Theme.Colors.accent)
                .task {
                    await appEnvironment.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            appEnvironment.handleScenePhase(phase)
        }
    }
}

extension SettingsStore.AppearanceMode {
    /// `nil` lets the system decide, which is what "System" means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

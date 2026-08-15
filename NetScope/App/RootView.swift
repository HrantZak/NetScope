import SwiftUI

/// Top-level tab container.
struct RootView: View {

    @Environment(AppEnvironment.self) private var app
    @State private var selectedTab: Tab = .devices

    enum Tab: String, Hashable, CaseIterable {
        case devices
        case network
        case activity
        case settings

        var title: String {
            switch self {
            case .devices: "Devices"
            case .network: "Network"
            case .activity: "Activity"
            case .settings: "Settings"
            }
        }

        var symbolName: String {
            switch self {
            case .devices: "rectangle.stack.fill"
            case .network: "wifi"
            case .activity: "chart.line.uptrend.xyaxis"
            case .settings: "gearshape.fill"
            }
        }
    }

    var body: some View {
        // The aurora lives inside each screen rather than behind the whole
        // `TabView`: a `NavigationStack` paints its own opaque backdrop, which
        // would cover anything sitting further back.
        ZStack {
            TabView(selection: $selectedTab) {
                DeviceListView()
                    .tag(Tab.devices)
                    .tabItem { Label(Tab.devices.title, systemImage: Tab.devices.symbolName) }

                NetworkView()
                    .tag(Tab.network)
                    .tabItem { Label(Tab.network.title, systemImage: Tab.network.symbolName) }

                ActivityView()
                    .tag(Tab.activity)
                    .tabItem { Label(Tab.activity.title, systemImage: Tab.activity.symbolName) }

                SettingsView()
                    .tag(Tab.settings)
                    .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.symbolName) }
            }
            .onChange(of: selectedTab) { _, _ in
                Haptics.selection()
            }
        }
        .overlay(alignment: .top) {
            PermissionBanner()
        }
    }
}

/// Slides in when Local Network access is missing — the one condition that
/// makes the entire app inert, so it deserves persistent, dismissible chrome.
private struct PermissionBanner: View {

    @Environment(AppEnvironment.self) private var app
    @State private var isDismissed = false

    var body: some View {
        if app.permission == .denied && !isDismissed {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Network access is off")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Enable it in Settings › Privacy › Local Network to scan.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    openSettings()
                } label: {
                    Text("Open")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.pressable)

                Button {
                    withAnimation(Theme.Motion.snappy) { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.pressable)
            }
            .glassSurface(cornerRadius: Theme.Radius.large, padding: Theme.Spacing.m)
            .padding(.horizontal, Theme.Spacing.l)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Theme.Motion.spring, value: app.permission)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview())
}

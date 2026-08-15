import SwiftUI

/// Scan tuning, appearance and privacy information.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var app
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack {
            Form {
                appearanceSection(settings)
                profileSection(settings)
                automationSection(settings)
                discoverySection(settings)
                performanceSection(settings)
                notificationsSection(settings)
                dataSection(settings)
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Reset scan settings?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset to defaults", role: .destructive) {
                    app.settings.resetScanSettings()
                    app.scanner.refreshAutoScan()
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private func appearanceSection(_ settings: SettingsStore) -> some View {
        Section {
            Picker(selection: Binding(
                get: { settings.appearance },
                set: { newValue in
                    Haptics.selection()
                    withAnimation(Theme.Motion.smooth) { app.settings.appearance = newValue }
                }
            )) {
                ForEach(SettingsStore.AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "paintbrush.fill")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Appearance")
        }
    }

    private func profileSection(_ settings: SettingsStore) -> some View {
        Section {
            Picker(selection: Binding(
                get: { settings.configuration.profile },
                set: { app.settings.configuration.profile = $0 }
            )) {
                ForEach(ScanConfiguration.Profile.allCases) { profile in
                    Label(profile.title, systemImage: profile.symbolName).tag(profile)
                }
            } label: {
                Label("Scan profile", systemImage: "slider.horizontal.3")
            }

            Text(settings.configuration.profile.detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)

            LabeledContent("Ports probed") {
                Text("\(settings.configuration.profile.ports.count)")
                    .font(.metric(14))
            }
        } header: {
            Text("Scanning")
        } footer: {
            Text("Thorough scans open far more connections and take noticeably longer on large networks.")
        }
    }

    private func automationSection(_ settings: SettingsStore) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.configuration.autoScanEnabled },
                set: { newValue in
                    app.settings.configuration.autoScanEnabled = newValue
                    app.scanner.refreshAutoScan()
                    Haptics.selection()
                }
            )) {
                Label("Automatic scanning", systemImage: "arrow.triangle.2.circlepath")
            }

            if settings.configuration.autoScanEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Every")
                        Spacer()
                        Text(intervalLabel(settings.configuration.autoScanInterval))
                            .font(.metric(14))
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    Slider(
                        value: Binding(
                            get: { settings.configuration.autoScanInterval },
                            set: { app.settings.configuration.autoScanInterval = $0 }
                        ),
                        in: 30...900,
                        step: 30
                    ) {
                        Text("Interval")
                    } onEditingChanged: { editing in
                        if !editing { app.scanner.refreshAutoScan() }
                    }
                }
            }
        } header: {
            Text("Automation")
        } footer: {
            Text("Automatic scans only run while NetScope is open — iOS does not allow continuous background network scanning.")
        }
    }

    private func discoverySection(_ settings: SettingsStore) -> some View {
        Section {
            Toggle(isOn: binding(\.resolveHostnames)) {
                Label("Resolve hostnames", systemImage: "text.cursor")
            }
            Toggle(isOn: binding(\.useBonjour)) {
                Label("Bonjour discovery", systemImage: "dot.radiowaves.left.and.right")
            }
            Toggle(isOn: binding(\.scanPorts)) {
                Label("Probe services", systemImage: "bolt.horizontal.circle")
            }
            Toggle(isOn: binding(\.useTCPFallback)) {
                Label("TCP fallback", systemImage: "arrow.uturn.down.circle")
            }
        } header: {
            Text("Discovery")
        } footer: {
            Text("TCP fallback finds hosts that ignore ping. It only kicks in when ICMP returns almost nothing, because it is much slower.")
        }
    }

    private func performanceSection(_ settings: SettingsStore) -> some View {
        Section {
            stepperRow(
                title: "Parallel hosts",
                systemImage: "square.stack.3d.down.right",
                value: Binding(
                    get: { settings.configuration.hostConcurrency },
                    set: { app.settings.configuration.hostConcurrency = $0 }
                ),
                range: 8...256,
                step: 8
            )

            stepperRow(
                title: "Parallel ports",
                systemImage: "arrow.triangle.branch",
                value: Binding(
                    get: { settings.configuration.portConcurrency },
                    set: { app.settings.configuration.portConcurrency = $0 }
                ),
                range: 4...64,
                step: 4
            )

            stepperRow(
                title: "Ping attempts",
                systemImage: "repeat",
                value: Binding(
                    get: { settings.configuration.pingAttempts },
                    set: { app.settings.configuration.pingAttempts = $0 }
                ),
                range: 1...5,
                step: 1
            )

            sliderRow(
                title: "Ping timeout",
                systemImage: "timer",
                value: Binding(
                    get: { settings.configuration.pingTimeout },
                    set: { app.settings.configuration.pingTimeout = $0 }
                ),
                range: 0.2...3,
                step: 0.1,
                format: { String(format: "%.1f s", $0) }
            )

            sliderRow(
                title: "Port timeout",
                systemImage: "timer",
                value: Binding(
                    get: { settings.configuration.portTimeout },
                    set: { app.settings.configuration.portTimeout = $0 }
                ),
                range: 0.2...3,
                step: 0.1,
                format: { String(format: "%.1f s", $0) }
            )

            stepperRow(
                title: "Max hosts",
                systemImage: "number",
                value: Binding(
                    get: { settings.configuration.maxHosts },
                    set: { app.settings.configuration.maxHosts = $0 }
                ),
                range: 64...4096,
                step: 64
            )
        } header: {
            Text("Performance")
        } footer: {
            Text("Higher parallelism finishes sooner but puts more load on the Wi-Fi radio. The defaults are tuned for a typical home network.")
        }
    }

    private func notificationsSection(_ settings: SettingsStore) -> some View {
        Section {
            Toggle(isOn: binding(\.notifyOnNewDevice)) {
                Label("New device joins", systemImage: "plus.circle")
            }
            Toggle(isOn: binding(\.notifyOnDeviceLeft)) {
                Label("Device leaves", systemImage: "minus.circle")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Delivered as local notifications while the app is running. iOS asks for permission the first time one is posted.")
        }
    }

    private func dataSection(_ settings: SettingsStore) -> some View {
        Section {
            stepperRow(
                title: "Keep history",
                systemImage: "calendar",
                value: Binding(
                    get: { settings.configuration.keepHistoryDays },
                    set: { app.settings.configuration.keepHistoryDays = $0 }
                ),
                range: 1...365,
                step: 1,
                suffix: "days"
            )

            LabeledContent {
                Text("\(app.repository.history.count)")
                    .font(.metric(14))
            } label: {
                Label("Stored devices", systemImage: "internaldrive")
            }

            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                Label("Reset scan settings", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Data")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: app.permission == .granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(app.permission == .granted ? Theme.Colors.online : Theme.Colors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Network access")
                        .font(.system(size: 14, weight: .medium))
                    Text(app.permission.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if app.permission != .granted {
                    Button("Request") {
                        Task { await app.requestPermission() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
            }

            LabeledContent("Version", value: appVersion)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Everything stays on this device", systemImage: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                Text("NetScope scans only the network you are connected to. Results are stored locally, no account is required, and nothing is ever uploaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("What iOS does not allow", systemImage: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Apps cannot read other devices' MAC addresses unless the system already has an ARP entry, cannot query exact hardware models, and cannot scan in the background. NetScope shows only what the platform makes available.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("About")
        }
    }

    // MARK: - Reusable rows

    private func stepperRow(
        title: String,
        systemImage: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String = ""
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(suffix.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(suffix)")
                    .font(.metric(14))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    private func sliderRow(
        title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.metric(14))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    /// Shorthand for toggles that write straight into `ScanConfiguration`.
    private func binding(_ keyPath: WritableKeyPath<ScanConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.settings.configuration[keyPath: keyPath] },
            set: { newValue in
                app.settings.configuration[keyPath: keyPath] = newValue
                Haptics.selection()
            }
        )
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds)) s"
            : "\(Int(seconds / 60)) min"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}

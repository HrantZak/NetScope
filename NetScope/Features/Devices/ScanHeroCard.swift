import SwiftUI

/// Hero card at the top of the device list: network identity, live scan state
/// and the primary Scan action.
struct ScanHeroCard: View {

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let scanner = app.scanner
        let snapshot = app.snapshot
        let progress = scanner.progress

        VStack(spacing: Theme.Spacing.l) {
            header(snapshot: snapshot)

            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                radar(progress: progress, isScanning: scanner.isScanning)

                VStack(alignment: .leading, spacing: 5) {
                    Text(scanner.isScanning ? progress.phase.title.uppercased() : "NETWORK OVERVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.Colors.accent)

                    Text("\(app.repository.devices.filter(\.isOnline).count) online")
                        .font(.metric(29, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())

                    Text(networkSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            metrics(scanner: scanner)
            discoveryStrip

            if scanner.isScanning {
                VStack(spacing: 6) {
                    HStack {
                        Text(progress.phase.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        if progress.totalHosts > 0 {
                            Text("\(progress.scannedHosts)/\(progress.totalHosts)")
                                .font(.technical(11))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .monospacedDigit()
                        }
                    }
                    ScanProgressBar(
                        fraction: progress.fraction,
                        isIndeterminate: progress.totalHosts == 0
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            actionRow(
                isScanning: scanner.isScanning,
                canScan: scanner.canScan && app.permission != .denied,
                permissionDenied: app.permission == .denied
            )

            if let error = scanner.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if let notice = scanner.lastNotice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .glassSurface(
            cornerRadius: Theme.Radius.extraLarge,
            padding: Theme.Spacing.l,
            tint: scanner.isScanning ? Theme.Colors.violet : Theme.Colors.accent
        )
        .animation(Theme.Motion.spring, value: app.scanner.isScanning)
    }

    // MARK: - Pieces

    private func header(snapshot: NetworkSnapshot) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: snapshot.interfaceType.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Gradients.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isConnected ? snapshot.displayName : "Not connected")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Text(subtitle(for: snapshot))
                    .font(.technical(11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func subtitle(for snapshot: NetworkSnapshot) -> String {
        guard snapshot.isConnected else { return "Join a Wi-Fi network to scan" }
        var parts: [String] = []
        if let local = snapshot.localAddress { parts.append(local.description) }
        if let subnet = snapshot.subnet { parts.append("/\(subnet.prefixLength)") }
        if let gateway = snapshot.gateway {
            parts.append(snapshot.gatewayIsInferred == true ? "gw ~\(gateway)" : "gw \(gateway)")
        }
        return parts.joined(separator: "  ")
    }

    private func radar(progress: ScanProgress, isScanning: Bool) -> some View {
        ZStack {
            RadarView(isActive: isScanning, blipCount: app.repository.devices.count)
                .frame(width: 96, height: 96)

            ProgressRing(fraction: isScanning ? progress.fraction : 1, lineWidth: 5)
                .frame(width: 96, height: 96)
                .opacity(isScanning ? 1 : 0.35)

            VStack(spacing: 0) {
                Text("\(app.repository.devices.count)")
                    .font(.metric(26, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text("devices")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(width: 96, height: 96)
        .animation(Theme.Motion.smooth, value: app.repository.devices.count)
    }

    private func metrics(scanner: ScanCoordinator) -> some View {
        let devices = app.repository.devices
        let online = devices.filter(\.isOnline).count
        let latencies = devices.compactMap(\.latencyMilliseconds)
        let average = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        return HStack(spacing: Theme.Spacing.s) {
            metricTile(
                symbol: "checkmark.circle.fill",
                tint: Theme.Colors.online,
                label: "Online",
                value: "\(online)"
            )
            metricTile(
                symbol: "timer",
                tint: Theme.Colors.latency(average),
                label: "Latency",
                value: Formatters.latency(average)
            )
            metricTile(
                symbol: "clock.arrow.circlepath",
                tint: Theme.Colors.violet,
                label: "Updated",
                value: scanner.lastCompletedAt.map { Formatters.relativeString(from: $0) } ?? "never"
            )
        }
    }

    private func metricTile(symbol: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)

            Text(value)
                .font(.metric(14, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private var networkSummary: String {
        let devices = app.repository.devices
        let remoteCount = devices.filter { !$0.isLocalDevice }.count
        let serviceCount = devices.filter { !$0.services.isEmpty }.count
        return "\(remoteCount) remote · \(serviceCount) with services"
    }

    private var discoveryStrip: some View {
        let devices = app.repository.devices
        let methods: [DiscoveryMethod] = [.icmp, .tcp, .bonjour, .arp, .route]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(methods, id: \.rawValue) { method in
                    let count = devices.filter { $0.discoveryMethod == method }.count
                    HStack(spacing: 5) {
                        Image(systemName: method.symbolName)
                            .font(.system(size: 9, weight: .bold))
                        Text(method.title)
                            .lineLimit(1)
                        Text("\(count)")
                            .font(.metric(10, weight: .bold))
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(count > 0 ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            count > 0
                                ? Theme.Colors.accent.opacity(0.12)
                                : Theme.Colors.surfaceSunken.opacity(0.7)
                        )
                    )
                }
            }
        }
        .accessibilityLabel("Discovery method summary")
    }

    private func actionRow(isScanning: Bool, canScan: Bool, permissionDenied: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                Haptics.medium()
                if permissionDenied {
                    openSystemSettings()
                } else if isScanning {
                    app.scanner.cancelScan()
                } else {
                    app.scanner.startScan()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                    Text(permissionDenied ? "Enable access" : (isScanning ? "Stop" : "Scan network"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(
                tint: isScanning
                    ? LinearGradient(colors: [Theme.Colors.rose, Theme.Colors.amber], startPoint: .leading, endPoint: .trailing)
                    : Theme.Gradients.accent
            ))
            .disabled(!permissionDenied && !canScan && !isScanning)
            .opacity(permissionDenied || canScan || isScanning ? 1 : 0.5)

            Button {
                Haptics.light()
                Task { await app.refreshNetworkInfo() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Colors.accent.opacity(0.12)))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Refresh network information")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

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
                metrics(progress: progress, scanner: scanner)
            }

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

            actionRow(isScanning: scanner.isScanning, canScan: scanner.canScan)

            if let error = scanner.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .glassSurface(cornerRadius: Theme.Radius.extraLarge, padding: Theme.Spacing.l)
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
        if let gateway = snapshot.gateway { parts.append("gw \(gateway)") }
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

    private func metrics(progress: ScanProgress, scanner: ScanCoordinator) -> some View {
        let devices = app.repository.devices
        let online = devices.filter(\.isOnline).count
        let latencies = devices.compactMap(\.latencyMilliseconds)
        let average = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            metricLine(
                symbol: "checkmark.circle.fill",
                tint: Theme.Colors.online,
                label: "Online",
                value: "\(online)"
            )
            metricLine(
                symbol: "timer",
                tint: Theme.Colors.latency(average),
                label: "Avg latency",
                value: Formatters.latency(average)
            )
            metricLine(
                symbol: "clock.arrow.circlepath",
                tint: Theme.Colors.textSecondary,
                label: "Last scan",
                value: scanner.lastCompletedAt.map { Formatters.relativeString(from: $0) } ?? "never"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricLine(symbol: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer(minLength: 4)

            Text(value)
                .font(.metric(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
        }
    }

    private func actionRow(isScanning: Bool, canScan: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                Haptics.medium()
                if isScanning {
                    app.scanner.cancelScan()
                } else {
                    app.scanner.startScan()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                    Text(isScanning ? "Stop" : "Scan network")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle(
                tint: isScanning
                    ? LinearGradient(colors: [Theme.Colors.rose, Theme.Colors.amber], startPoint: .leading, endPoint: .trailing)
                    : Theme.Gradients.accent
            ))
            .disabled(!canScan && !isScanning)
            .opacity(canScan || isScanning ? 1 : 0.5)

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
}

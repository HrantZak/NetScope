import SwiftUI
import Charts

/// Connection details for the current network plus aggregate statistics.
struct NetworkView: View {

    @Environment(AppEnvironment.self) private var app
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    connectionCard
                    addressingCard
                    statisticsGrid
                    compositionCard
                    latencyDistributionCard
                    trendCard
                    topPortsCard
                    smartChecksCard
                    permissionCard
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background { AuroraBackground() }
            .scrollIndicators(.hidden)
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
    }

    // MARK: - Smart checks

    private var smartChecksCard: some View {
        let checks = NetworkAudit.checks(snapshot: app.snapshot, devices: app.repository.devices)

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "20 smart checks",
                subtitle: "Connection, discovery, identity and exposed services",
                systemImage: "checkmark.shield.fill",
                accessory: AnyView(
                    Button {
                        copyAuditReport(checks)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Copy audit report")
                )
            )

            VStack(spacing: 0) {
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        Image(systemName: check.level.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(auditColor(check.level))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(check.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)

                    if check.id != checks.last?.id { Divider() }
                }
            }
        }
        .cardSurface()
    }

    private func auditColor(_ level: NetworkAudit.Level) -> Color {
        switch level {
        case .good: Theme.Colors.online
        case .info: Theme.Colors.accent
        case .warning: Theme.Colors.warning
        }
    }

    private func copyAuditReport(_ checks: [NetworkAudit.Check]) {
        let lines = checks.map { check in
            let marker = check.level == .warning ? "⚠︎" : (check.level == .good ? "✓" : "•")
            return "\(marker) \(check.title): \(check.detail)"
        }
        let heading = "NetScope audit — \(app.snapshot.displayName)"
        UIPasteboard.general.string = ([heading, ""] + lines).joined(separator: "\n")
        Haptics.success()
    }

    // MARK: - Connection

    private var connectionCard: some View {
        let snapshot = app.snapshot

        return VStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(snapshot.isConnected
                              ? AnyShapeStyle(Theme.Gradients.accent)
                              : AnyShapeStyle(Theme.Colors.offline))
                        .frame(width: 52, height: 52)
                    Image(systemName: snapshot.interfaceType.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.isConnected ? snapshot.displayName : "Not connected")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        TagPill(text: snapshot.interfaceType.title, color: Theme.Colors.accent)
                        if let interfaceName = snapshot.interfaceName {
                            TagPill(text: interfaceName, color: Theme.Colors.textTertiary)
                        }
                        if let secure = snapshot.isSecure {
                            TagPill(
                                text: secure ? "Secured" : "Open",
                                systemImage: secure ? "lock.fill" : "lock.open.fill",
                                color: secure ? Theme.Colors.online : Theme.Colors.warning
                            )
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if snapshot.ssid == nil && snapshot.interfaceType == .wifi {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("The Wi-Fi network name requires the Access Wi-Fi Information capability. Without it, NetScope identifies the network by its subnet instead — scanning is unaffected.")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .glassSurface(cornerRadius: Theme.Radius.extraLarge, padding: Theme.Spacing.l)
    }

    // MARK: - Addressing

    private var addressingCard: some View {
        let snapshot = app.snapshot

        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Addressing", systemImage: "point.3.filled.connected.trianglepath.dotted")

            VStack(spacing: 0) {
                DetailRow(label: "Local IP", value: snapshot.localAddress?.description, systemImage: "iphone")
                Divider()
                DetailRow(label: "Subnet mask", value: snapshot.netmask?.description, systemImage: "square.grid.3x3")
                Divider()
                DetailRow(label: "Network", value: snapshot.subnet?.description, systemImage: "network")
                Divider()
                DetailRow(
                    label: snapshot.gatewayIsInferred == true ? "Gateway (inferred)" : "Gateway",
                    value: snapshot.gateway?.description,
                    systemImage: "arrow.triangle.branch"
                )
                Divider()
                DetailRow(label: "Broadcast", value: snapshot.broadcast?.description, systemImage: "dot.radiowaves.left.and.right")
                Divider()
                DetailRow(
                    label: snapshot.dnsServersAreInferred ? "DNS (inferred)" : "DNS servers",
                    value: snapshot.dnsServers.isEmpty
                        ? nil
                        : snapshot.dnsServers.map(\.description).joined(separator: "\n"),
                    systemImage: "server.rack"
                )
                Divider()
                DetailRow(
                    label: "Addressable hosts",
                    value: snapshot.subnet.map { "\($0.usableHostCount)" },
                    systemImage: "number",
                    isMonospaced: false
                )
                if let vendor = snapshot.externalRouterVendor {
                    Divider()
                    DetailRow(label: "Router vendor", value: vendor, systemImage: "wifi.router", isMonospaced: false)
                }
            }

            if snapshot.dnsServersAreInferred {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("iOS gives apps no way to read the resolver configuration, so the gateway is shown — it is the DNS server on most home networks, but it is a deduction, not a measurement.")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.top, Theme.Spacing.s)
            }
        }
        .cardSurface()
    }

    // MARK: - Statistics

    private var statisticsGrid: some View {
        let statistics = app.repository.statistics

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)],
            spacing: Theme.Spacing.m
        ) {
            StatTile(
                title: "Devices",
                value: "\(statistics.totalDevices)",
                systemImage: "rectangle.stack.fill",
                tint: Theme.Colors.accent,
                caption: "\(statistics.onlineDevices) online · \(statistics.offlineDevices) offline"
            )
            StatTile(
                title: "Avg latency",
                value: Formatters.latency(statistics.averageLatency),
                systemImage: "timer",
                tint: Theme.Colors.latency(statistics.averageLatency),
                caption: statistics.fastestDevice.map { "fastest \($0.displayName)" }
            )
            StatTile(
                title: "With services",
                value: "\(statistics.devicesWithServices)",
                systemImage: "bolt.horizontal.circle",
                tint: Theme.Colors.violet,
                caption: "open TCP ports found"
            )
            StatTile(
                title: "Identified",
                value: "\(statistics.identifiedVendors)",
                systemImage: "building.2.fill",
                tint: Theme.Colors.mint,
                caption: "vendor known"
            )
        }
    }

    private var compositionCard: some View {
        let buckets = app.repository.statistics.kindBuckets

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Device types", systemImage: "chart.bar.fill")

            if buckets.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Count", bucket.count),
                        y: .value("Type", bucket.label)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(Theme.Gradients.accent)
                    .annotation(position: .trailing) {
                        Text("\(bucket.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(height: CGFloat(buckets.count) * 30 + 20)
            }
        }
        .cardSurface()
    }

    private var latencyDistributionCard: some View {
        let buckets = app.repository.statistics.latencyBuckets
        let hasData = buckets.contains { $0.count > 0 }

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Latency distribution", systemImage: "chart.bar.xaxis")

            if !hasData {
                emptyChartPlaceholder
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Band", bucket.label),
                        y: .value("Devices", bucket.count)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(by: .value("Band", bucket.label))
                }
                .chartForegroundStyleScale([
                    "< 10 ms": Theme.Colors.online,
                    "10–50 ms": Theme.Colors.mint,
                    "50–200 ms": Theme.Colors.warning,
                    "> 200 ms": Theme.Colors.danger
                ])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.Colors.hairline)
                        AxisValueLabel().font(.system(size: 10))
                    }
                }
                .frame(height: 160)
            }
        }
        .cardSurface()
    }

    private var trendCard: some View {
        let samples = app.repository.samplesForCurrentNetwork.suffix(40)

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "Scan history",
                subtitle: samples.isEmpty ? "No scans recorded yet" : "\(samples.count) recent scans",
                systemImage: "chart.xyaxis.line"
            )

            if samples.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(Array(samples)) { sample in
                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("Devices", sample.deviceCount)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.Colors.accent.opacity(0.30), Theme.Colors.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Devices", sample.deviceCount)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Theme.Gradients.accent)

                        PointMark(
                            x: .value("Time", sample.date),
                            y: .value("Online", sample.onlineCount)
                        )
                        .symbolSize(18)
                        .foregroundStyle(Theme.Colors.mint)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.Colors.hairline)
                        AxisValueLabel().font(.system(size: 10))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.system(size: 9))
                    }
                }
                .frame(height: 160)

                HStack(spacing: Theme.Spacing.l) {
                    legendDot(color: Theme.Colors.accent, label: "Known devices")
                    legendDot(color: Theme.Colors.mint, label: "Online")
                    Spacer()
                    if let last = samples.last {
                        Text("last scan \(Formatters.duration(last.scanDuration))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .cardSurface()
    }

    private var topPortsCard: some View {
        let ports = app.repository.statistics.topPorts

        return Group {
            if !ports.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader("Most common services", systemImage: "bolt.horizontal.circle")

                    VStack(spacing: 0) {
                        ForEach(ports) { bucket in
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: bucket.symbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.violet)
                                    .frame(width: 20)

                                Text(bucket.label)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: Theme.Spacing.s)

                                Text("\(bucket.count)")
                                    .font(.metric(13))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .padding(.vertical, 8)

                            if bucket.id != ports.last?.id { Divider() }
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private var permissionCard: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: app.permission == .granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(app.permission == .granted ? Theme.Colors.online : Theme.Colors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Network access")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(app.permission.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            if app.permission != .granted {
                Button("Request") {
                    Haptics.light()
                    Task { await app.requestPermission() }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.pressable)
            }
        }
        .cardSurface(padding: Theme.Spacing.m)
    }

    // MARK: - Helpers

    private var emptyChartPlaceholder: some View {
        Text("Not enough data yet. Run a scan to populate this chart.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .multilineTextAlignment(.center)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await app.refreshNetworkInfo()
    }
}

#Preview {
    NetworkView()
        .environment(AppEnvironment.preview())
}

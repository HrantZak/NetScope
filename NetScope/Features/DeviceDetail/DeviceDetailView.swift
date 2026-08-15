import SwiftUI
import Charts

/// Everything known about one host, plus live diagnostics.
///
/// Takes a device **id** rather than a `Device` value so the screen keeps
/// updating as new scans refresh the record underneath it.
struct DeviceDetailView: View {

    let deviceID: String

    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var model = DeviceDetailViewModel()
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var draftNotes = ""
    @State private var isEditingNotes = false

    private var device: Device? {
        app.repository.device(with: deviceID)
    }

    var body: some View {
        Group {
            if let device {
                content(for: device)
            } else {
                EmptyStateView(
                    title: "Device removed",
                    message: "This device is no longer in your history.",
                    systemImage: "questionmark.circle"
                )
            }
        }
        .background { AuroraBackground() }
        .navigationTitle(device?.displayName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let device {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        app.repository.toggleFavorite(device)
                    } label: {
                        Image(systemName: device.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(device.isFavorite ? Theme.Colors.amber : Theme.Colors.accent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(device.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
        .onDisappear { model.cancelAll() }
        .task(id: deviceID) {
            guard let device else { return }
            await model.fingerprintWebService(for: device)
        }
        .alert("Rename device", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let device else { return }
                app.repository.rename(device, to: draftName)
                Haptics.success()
            }
        } message: {
            Text("This name is only stored on your device.")
        }
    }

    // MARK: - Content

    private func content(for device: Device) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                headerCard(device)
                actionsCard(device)

                if !model.pingSamples.isEmpty {
                    latencyCard
                }

                overviewCard(device)
                servicesCard(device)
                notesCard(device)
                timelineCard(device)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    private func headerCard(_ device: Device) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            DeviceIcon(kind: device.kind, size: 76, isOnline: device.isOnline)

            VStack(spacing: 6) {
                Button {
                    draftName = device.customName ?? device.displayName
                    isRenaming = true
                    Haptics.light()
                } label: {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.pressable)

                Text(device.ipAddress.description)
                    .font(.technical(15, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: Theme.Spacing.s) {
                TagPill(
                    text: device.isOnline ? "Online" : "Offline",
                    systemImage: device.isOnline ? "checkmark.circle.fill" : "moon.zzz.fill",
                    color: device.isOnline ? Theme.Colors.online : Theme.Colors.offline,
                    filled: true
                )
                TagPill(text: device.kind.title, systemImage: device.kind.symbolName, color: Theme.Colors.kind(device.kind))
                if device.isGateway {
                    TagPill(text: "Gateway", systemImage: "arrow.triangle.branch", color: Theme.Colors.accent)
                }
                if device.isLocalDevice {
                    TagPill(text: "This device", systemImage: "iphone", color: Theme.Colors.mint)
                }
            }

            LatencyBadge(milliseconds: device.latencyMilliseconds)
        }
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: Theme.Radius.extraLarge, padding: Theme.Spacing.xl)
    }

    // MARK: Actions

    private func actionsCard(_ device: Device) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                actionButton(
                    title: model.isPinging ? "Stop ping" : "Ping",
                    systemImage: model.isPinging ? "stop.circle.fill" : "wave.3.right",
                    tint: model.isPinging ? Theme.Colors.rose : Theme.Colors.accent
                ) {
                    Haptics.medium()
                    model.togglePing(for: device, timeout: app.settings.configuration.pingTimeout)
                }

                actionButton(
                    title: model.isScanningPorts ? "Stop scan" : "Scan ports",
                    systemImage: model.isScanningPorts ? "stop.circle.fill" : "bolt.horizontal.circle",
                    tint: model.isScanningPorts ? Theme.Colors.rose : Theme.Colors.violet
                ) {
                    Haptics.medium()
                    if model.isScanningPorts {
                        model.stopPortScan()
                    } else {
                        model.startPortScan(for: device, configuration: app.settings.configuration)
                    }
                }
            }

            HStack(spacing: Theme.Spacing.s) {
                actionButton(
                    title: "Check",
                    systemImage: "checkmark.shield",
                    tint: Theme.Colors.mint,
                    isBusy: model.isCheckingReachability
                ) {
                    Haptics.light()
                    Task { await model.checkReachability(for: device) }
                }

                if let url = model.webURL(for: device) {
                    actionButton(title: "Open web", systemImage: "safari", tint: Theme.Colors.amber) {
                        Haptics.light()
                        openURL(url)
                    }
                }

                actionButton(title: "Copy IP", systemImage: "doc.on.doc", tint: Theme.Colors.textSecondary) {
                    UIPasteboard.general.string = device.ipAddress.description
                    Haptics.success()
                }
            }

            if model.isScanningPorts {
                VStack(spacing: 6) {
                    HStack {
                        Text("Probing \(model.totalPortCount) ports…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text("\(model.scannedPortCount)/\(model.totalPortCount)")
                            .font(.technical(11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    ScanProgressBar(fraction: model.portScanFraction)
                }
                .transition(.opacity)
            }

            if let result = model.lastReachabilityResult, let checked = model.lastReachabilityCheck {
                Label(
                    result
                        ? "Reachable · checked \(Formatters.relativeString(from: checked))"
                        : "No response · checked \(Formatters.relativeString(from: checked))",
                    systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(result ? Theme.Colors.online : Theme.Colors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
        .animation(Theme.Motion.snappy, value: model.isScanningPorts)
        .animation(Theme.Motion.snappy, value: model.lastReachabilityResult)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .frame(height: 20)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: 20)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.pressable)
    }

    // MARK: Latency chart

    private var latencyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "Latency",
                subtitle: model.isPinging ? "Live · one probe per second" : "Last session",
                systemImage: "waveform.path.ecg"
            )

            Chart {
                ForEach(model.pingSamples) { sample in
                    if let milliseconds = sample.milliseconds {
                        AreaMark(
                            x: .value("Sample", sample.id),
                            y: .value("Latency", milliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.Colors.accent.opacity(0.35), Theme.Colors.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Sample", sample.id),
                            y: .value("Latency", milliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Theme.Gradients.accent)
                    } else {
                        // Timeouts are marked rather than interpolated over.
                        PointMark(x: .value("Sample", sample.id), y: .value("Latency", 0))
                            .symbol(.cross)
                            .foregroundStyle(Theme.Colors.danger)
                    }
                }

                if let average = model.averageLatency {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(Formatters.latency(average))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.Colors.hairline)
                    AxisValueLabel {
                        if let milliseconds = value.as(Double.self) {
                            Text("\(Int(milliseconds))")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 150)
            .animation(Theme.Motion.smooth, value: model.pingSamples.count)

            HStack(spacing: Theme.Spacing.m) {
                statisticColumn("Min", Formatters.latency(model.minimumLatency))
                statisticColumn("Avg", Formatters.latency(model.averageLatency))
                statisticColumn("Max", Formatters.latency(model.maximumLatency))
                statisticColumn("Jitter", Formatters.latency(model.jitter))
                statisticColumn("Loss", String(format: "%.0f%%", model.packetLossPercentage))
            }
        }
        .cardSurface()
    }

    private func statisticColumn(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.metric(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Overview

    private func overviewCard(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Overview", systemImage: "info.circle")

            VStack(spacing: 0) {
                DetailRow(label: "IP address", value: device.ipAddress.description, systemImage: "number")
                Divider()
                DetailRow(
                    label: "MAC address",
                    value: Formatters.macDescription(device.macAddress),
                    systemImage: "barcode"
                )
                Divider()
                DetailRow(label: "Vendor", value: device.vendor, systemImage: "building.2", isMonospaced: false)
                Divider()
                DetailRow(label: "Hostname", value: device.hostname, systemImage: "text.cursor")
                Divider()
                DetailRow(
                    label: "Bonjour name",
                    value: device.bonjourName,
                    systemImage: "dot.radiowaves.left.and.right",
                    isMonospaced: false
                )
                Divider()
                DetailRow(
                    label: "Detected as",
                    value: device.kind.title,
                    systemImage: "sparkle.magnifyingglass",
                    isMonospaced: false
                )
                Divider()
                DetailRow(
                    label: "Found via",
                    value: device.discoveryMethod.title,
                    systemImage: "antenna.radiowaves.left.and.right",
                    isMonospaced: false
                )
            }

            if device.macAddress == nil {
                privacyNote(
                    "iOS only exposes a MAC address when the system has a recent ARP entry for the host. Without it the hardware vendor cannot be identified."
                )
            } else if let mac = device.macAddress, VendorDatabase.isRandomized(mac: mac) {
                privacyNote(
                    "This device uses a private (randomised) Wi-Fi address, so its real hardware vendor is intentionally hidden."
                )
            }
        }
        .cardSurface()
    }

    private func privacyNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: Services

    private func servicesCard(_ device: Device) -> some View {
        let services = model.liveServices.isEmpty ? device.services : model.liveServices

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "Services",
                subtitle: services.isEmpty ? "No open ports found yet" : "\(services.count) reachable",
                systemImage: "bolt.horizontal.circle"
            )

            if services.isEmpty {
                Text("Run a port scan to look for services on this host.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(services) { service in
                        serviceRow(service)
                        if service.id != services.last?.id { Divider() }
                    }
                }
            }

            if let fingerprint = model.fingerprint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Web service")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(fingerprint.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let server = fingerprint.server {
                        Text(server)
                            .font(.technical(11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(Theme.Colors.surfaceSunken)
                )
            }

            if !device.bonjourServiceTypes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Advertised over Bonjour")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    FlowLayout(spacing: 6) {
                        ForEach(device.bonjourServiceTypes, id: \.self) { type in
                            TagPill(text: PortCatalog.bonjourLabel(for: type), color: Theme.Colors.mint)
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private func serviceRow(_ service: ServiceInfo) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: service.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.violet)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let detail = service.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            if service.discoveredViaBonjour {
                TagPill(text: "mDNS", color: Theme.Colors.mint)
            }

            Text(":\(service.port)")
                .font(.technical(12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 9)
    }

    // MARK: Notes

    private func notesCard(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "Notes",
                systemImage: "note.text",
                accessory: AnyView(
                    Button(isEditingNotes ? "Save" : "Edit") {
                        if isEditingNotes {
                            app.repository.updateNotes(device, notes: draftNotes)
                            Haptics.success()
                        } else {
                            draftNotes = device.notes ?? ""
                        }
                        withAnimation(Theme.Motion.snappy) { isEditingNotes.toggle() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                )
            )

            if isEditingNotes {
                TextEditor(text: $draftNotes)
                    .font(.system(size: 14))
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .fill(Theme.Colors.surfaceSunken)
                    )
            } else {
                Text(device.notes ?? "No notes yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(device.notes == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    // MARK: Timeline

    private func timelineCard(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("History", systemImage: "clock.arrow.circlepath")

            VStack(spacing: 0) {
                DetailRow(
                    label: "First seen",
                    value: Formatters.dateTime.string(from: device.firstSeen),
                    systemImage: "calendar.badge.plus",
                    isMonospaced: false
                )
                Divider()
                DetailRow(
                    label: "Last seen",
                    value: "\(Formatters.dateTime.string(from: device.lastSeen)) (\(Formatters.relativeString(from: device.lastSeen)))",
                    systemImage: "calendar.badge.clock",
                    isMonospaced: false
                )
                Divider()
                DetailRow(
                    label: "Seen in scans",
                    value: "\(device.timesSeen)",
                    systemImage: "number.circle",
                    isMonospaced: false
                )
                Divider()
                DetailRow(
                    label: "Network",
                    value: device.networkID.replacingOccurrences(of: "ssid:", with: ""),
                    systemImage: "wifi",
                    isMonospaced: false
                )
            }

            if device.latencySamples.count > 2 {
                sparkline(for: device)
            }
        }
        .cardSurface()
    }

    private func sparkline(for device: Device) -> some View {
        let points = Array(device.latencySamples.suffix(30).enumerated())

        return VStack(alignment: .leading, spacing: 6) {
            Text("Latency across recent scans")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)

            Chart {
                ForEach(points, id: \.offset) { point in
                    LineMark(
                        x: .value("Scan", point.offset),
                        y: .value("Latency", point.element * 1000)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .foregroundStyle(Theme.Gradients.success)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 44)
        }
        .padding(.top, Theme.Spacing.s)
    }
}

// MARK: - Flow layout

/// Wraps children onto as many lines as needed — SwiftUI has no built-in
/// equivalent, and a fixed `LazyVGrid` would leave ragged gaps between pills of
/// wildly different widths.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, currentRowWidth > 0 {
                totalHeight += currentRowHeight + spacing
                totalWidth = max(totalWidth, currentRowWidth - spacing)
                currentRowWidth = 0
                currentRowHeight = 0
            }
            currentRowWidth += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }

        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentRowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        DeviceDetailView(deviceID: Device.previewSamples[1].id)
            .environment(AppEnvironment.preview())
    }
}

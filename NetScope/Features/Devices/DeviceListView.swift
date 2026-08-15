import SwiftUI

/// Main screen: scan control plus the device list in four layouts.
struct DeviceListView: View {

    @Environment(AppEnvironment.self) private var app

    @State private var model = DeviceListViewModel()
    @State private var exportedFile: ExportedFile?
    @State private var isPreparingExport = false
    @State private var isShowingFilters = false
    @State private var exportError: String?

    var body: some View {
        @Bindable var settings = app.settings

        NavigationStack {
            Group {
                if settings.browse.layout == .grid {
                    gridContent
                } else {
                    listContent
                }
            }
            .background { AuroraBackground() }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: Device.self) { device in
                DeviceDetailView(deviceID: device.id)
            }
            .refreshable {
                await runScanAndWait()
            }
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingFilters) {
                FilterSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "Export failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
        .onAppear { syncModel() }
        .onChange(of: app.repository.devices) { _, _ in syncModel() }
        .onChange(of: app.settings.browse) { _, _ in syncModel() }
        .onChange(of: app.snapshot.networkID) { _, _ in syncModel() }
    }

    // MARK: - List layouts

    private var listContent: some View {
        List {
            heroSection
            controlsSection

            if model.sections.isEmpty {
                emptySection
            } else {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.devices) { device in
                            deviceRow(device)
                        }
                    } header: {
                        if model.isGrouped {
                            groupHeader(section)
                        }
                    }
                }
            }

            Color.clear
                .frame(height: 24)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 8)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.l, pinnedViews: []) {
                ScanHeroCard()
                controlsStack

                if model.sections.isEmpty {
                    emptyState
                        .padding(.top, Theme.Spacing.xxl)
                } else {
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            if model.isGrouped {
                                groupHeader(section)
                            }
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)],
                                spacing: Theme.Spacing.m
                            ) {
                                ForEach(section.devices) { device in
                                    NavigationLink(value: device) {
                                        DeviceGridCard(device: device)
                                    }
                                    .buttonStyle(.pressable)
                                    .contextMenu { contextMenu(for: device) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            ScanHeroCard()
                .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.l, bottom: Theme.Spacing.s, trailing: Theme.Spacing.l))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var controlsSection: some View {
        Section {
            controlsStack
                .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.l, bottom: Theme.Spacing.m, trailing: Theme.Spacing.l))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var controlsStack: some View {
        VStack(spacing: Theme.Spacing.m) {
            SearchField(text: Binding(
                get: { model.searchText },
                set: { model.updateSearch($0) }
            ))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(BrowsePreferences.StatusFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            systemImage: filter.symbolName,
                            isSelected: app.settings.browse.statusFilter == filter
                        ) {
                            Haptics.selection()
                            withAnimation(Theme.Motion.snappy) {
                                app.settings.browse.statusFilter = filter
                            }
                        }
                    }

                    Divider().frame(height: 20)

                    FilterChip(
                        title: app.settings.browse.kindFilter.isEmpty
                            ? "Type"
                            : "\(app.settings.browse.kindFilter.count) types",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: !app.settings.browse.kindFilter.isEmpty
                    ) {
                        Haptics.light()
                        isShowingFilters = true
                    }
                }
                .padding(.horizontal, 2)
            }

            if model.isFiltering {
                HStack(spacing: 6) {
                    Text("Showing \(model.visibleCount) of \(model.totalCount)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Spacer()

                    Button("Clear") {
                        Haptics.light()
                        withAnimation(Theme.Motion.snappy) {
                            model.updateSearch("")
                            app.settings.browse.statusFilter = .all
                            app.settings.browse.kindFilter = []
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .transition(.opacity)
            }

            if app.settings.browse.layout == .table {
                DeviceTableHeader()
            }
        }
        .animation(Theme.Motion.snappy, value: model.isFiltering)
    }

    private var emptySection: some View {
        Section {
            emptyState
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xl)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !app.snapshot.isConnected {
            EmptyStateView(
                title: "Not connected",
                message: "NetScope needs a Wi-Fi connection to look for devices on your local network.",
                systemImage: "wifi.slash"
            )
        } else if app.permission == .denied {
            EmptyStateView(
                title: "Local Network access needed",
                message: "iOS requires your permission before an app can see other devices. Enable NetScope in Settings › Privacy & Security › Local Network.",
                systemImage: "hand.raised.fill",
                actionTitle: "Open Settings",
                action: openSystemSettings
            )
        } else if model.totalCount == 0 {
            if app.scanner.isScanning {
                EmptyStateView(
                    title: "Scanning…",
                    message: "Hosts appear here the moment they answer.",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            } else {
                EmptyStateView(
                    title: "No devices yet",
                    message: "Run a scan to discover everything on \(app.snapshot.displayName).",
                    systemImage: "antenna.radiowaves.left.and.right",
                    actionTitle: "Scan now",
                    action: { app.scanner.startScan() }
                )
            }
        } else {
            EmptyStateView(
                title: "No matches",
                message: "No device matches the current search and filters.",
                systemImage: "magnifyingglass",
                actionTitle: "Clear filters",
                action: {
                    withAnimation(Theme.Motion.snappy) {
                        model.updateSearch("")
                        app.settings.browse.statusFilter = .all
                        app.settings.browse.kindFilter = []
                    }
                }
            )
        }
    }

    private func groupHeader(_ section: DeviceSection) -> some View {
        HStack(spacing: 6) {
            if let symbol = section.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .bold))
            Text("\(section.count)")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.Colors.accent.opacity(0.15)))
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.l, bottom: 4, trailing: Theme.Spacing.l))
    }

    // MARK: - Rows

    @ViewBuilder
    private func deviceRow(_ device: Device) -> some View {
        NavigationLink(value: device) {
            switch app.settings.browse.layout {
            case .comfortable:
                DeviceCardRow(device: device)
                    .cardSurface(padding: Theme.Spacing.m, isHighlighted: device.isGateway)
            case .compact:
                DeviceCompactRow(device: device)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .fill(Theme.Colors.surface)
                    )
            case .table:
                DeviceTableRow(device: device)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.Colors.surface)
                    )
            case .grid:
                DeviceGridCard(device: device)
            }
        }
        .listRowInsets(EdgeInsets(
            top: 3,
            leading: Theme.Spacing.l,
            bottom: 3,
            trailing: Theme.Spacing.l
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleFavorite(device)
            } label: {
                Label(
                    device.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: device.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(Theme.Colors.amber)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Haptics.warning()
                withAnimation(Theme.Motion.listItem) {
                    app.repository.remove(device)
                }
            } label: {
                Label("Forget", systemImage: "trash")
            }
        }
        .contextMenu { contextMenu(for: device) }
    }

    @ViewBuilder
    private func contextMenu(for device: Device) -> some View {
        Button {
            UIPasteboard.general.string = device.ipAddress.description
            Haptics.success()
        } label: {
            Label("Copy IP address", systemImage: "doc.on.doc")
        }

        if let mac = device.macAddress {
            Button {
                UIPasteboard.general.string = mac
                Haptics.success()
            } label: {
                Label("Copy MAC address", systemImage: "barcode")
            }
        }

        Button {
            toggleFavorite(device)
        } label: {
            Label(
                device.isFavorite ? "Remove from favorites" : "Add to favorites",
                systemImage: device.isFavorite ? "star.slash" : "star"
            )
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(Theme.Motion.listItem) {
                app.repository.remove(device)
            }
        } label: {
            Label("Forget device", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Layout", selection: layoutBinding) {
                    ForEach(BrowsePreferences.LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                    }
                }
            } label: {
                Image(systemName: app.settings.browse.layout.symbolName)
            }
            .accessibilityLabel("Change layout")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Sort by") {
                    Picker("Sort by", selection: sortFieldBinding) {
                        ForEach(BrowsePreferences.SortField.allCases) { field in
                            Label(field.title, systemImage: field.symbolName).tag(field)
                        }
                    }
                }

                Section {
                    Toggle(isOn: sortAscendingBinding) {
                        Label("Ascending", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section("Group by") {
                    Picker("Group by", selection: groupBinding) {
                        ForEach(BrowsePreferences.GroupField.allCases) { field in
                            Text(field.title).tag(field)
                        }
                    }
                }

                Section("Export \(model.visibleCount) devices") {
                    ForEach(ExportService.Format.allCases) { format in
                        Button {
                            export(format)
                        } label: {
                            Label("Export \(format.title)", systemImage: format.symbolName)
                        }
                    }
                }
            } label: {
                if isPreparingExport {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .accessibilityLabel("Sorting and export options")
        }
    }

    // MARK: - Bindings

    private var layoutBinding: Binding<BrowsePreferences.LayoutMode> {
        Binding(
            get: { app.settings.browse.layout },
            set: { newValue in
                Haptics.selection()
                withAnimation(Theme.Motion.snappy) { app.settings.browse.layout = newValue }
            }
        )
    }

    private var sortFieldBinding: Binding<BrowsePreferences.SortField> {
        Binding(
            get: { app.settings.browse.sortField },
            set: { newValue in
                Haptics.selection()
                withAnimation(Theme.Motion.snappy) { app.settings.browse.sortField = newValue }
            }
        )
    }

    private var sortAscendingBinding: Binding<Bool> {
        Binding(
            get: { app.settings.browse.sortAscending },
            set: { newValue in
                Haptics.selection()
                withAnimation(Theme.Motion.snappy) { app.settings.browse.sortAscending = newValue }
            }
        )
    }

    private var groupBinding: Binding<BrowsePreferences.GroupField> {
        Binding(
            get: { app.settings.browse.group },
            set: { newValue in
                Haptics.selection()
                withAnimation(Theme.Motion.snappy) { app.settings.browse.group = newValue }
            }
        )
    }

    // MARK: - Actions

    private func syncModel() {
        model.sync(devices: app.repository.devices, preferences: app.settings.browse)
    }

    private func toggleFavorite(_ device: Device) {
        Haptics.light()
        withAnimation(Theme.Motion.listItem) {
            app.repository.toggleFavorite(device)
        }
    }

    /// Pull-to-refresh has to stay awaited until the scan actually finishes,
    /// otherwise the spinner snaps away immediately.
    private func runScanAndWait() async {
        guard !app.scanner.isScanning else { return }
        app.scanner.startScan()

        // The scan may be queued behind a previous one unwinding, so wait for
        // it to actually begin before waiting for it to end — otherwise the
        // refresh spinner snaps away immediately.
        let deadline = Date.now.addingTimeInterval(3)
        while !app.scanner.isScanning, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(60))
        }

        while app.scanner.isScanning {
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func export(_ format: ExportService.Format) {
        guard !isPreparingExport else { return }
        isPreparingExport = true

        let devices = model.sections.flatMap(\.devices)
        let snapshot = app.snapshot

        Task {
            defer { isPreparingExport = false }
            do {
                let url = try await ExportService.makeFile(
                    devices: devices,
                    snapshot: snapshot,
                    format: format
                )
                exportedFile = ExportedFile(url: url)
                Haptics.success()
            } catch {
                exportError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    DeviceListView()
        .environment(AppEnvironment.preview())
}

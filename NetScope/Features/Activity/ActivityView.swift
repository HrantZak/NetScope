import SwiftUI

/// Event timeline, full device history and favourites.
struct ActivityView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case timeline
        case history
        case favorites

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline: "Timeline"
            case .history: "History"
            case .favorites: "Favorites"
            }
        }
    }

    @Environment(AppEnvironment.self) private var app
    @State private var mode: Mode = .timeline
    @State private var searchText = ""
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
                .onChange(of: mode) { _, _ in Haptics.selection() }

                content
            }
            .background { AuroraBackground() }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Device.self) { device in
                DeviceDetailView(deviceID: device.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            isConfirmingClear = true
                        } label: {
                            Label("Clear history", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Clear history?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear everything except this network", role: .destructive) {
                    app.repository.clearHistory(keepingCurrentNetwork: true)
                    Haptics.warning()
                }
                Button("Clear everything", role: .destructive) {
                    app.repository.clearHistory(keepingCurrentNetwork: false)
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Devices, events and scan statistics will be deleted. Favorites are removed too.")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .timeline: timelineList
        case .history: historyList
        case .favorites: favoritesList
        }
    }

    private var timelineList: some View {
        Group {
            if app.repository.events.isEmpty {
                EmptyStateView(
                    title: "No activity yet",
                    message: "Changes to your network — devices joining or leaving — will show up here after a few scans.",
                    systemImage: "bell.badge"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedEvents, id: \.key) { group in
                        Section {
                            ForEach(group.events) { event in
                                eventRow(event)
                            }
                        } header: {
                            Text(group.key)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var historyList: some View {
        Group {
            if filteredHistory.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "Nothing recorded yet" : "No matches",
                    message: searchText.isEmpty
                        ? "Every device NetScope has ever seen, on any network, is listed here."
                        : "No device in your history matches “\(searchText)”.",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredHistory) { device in
                        NavigationLink(value: device) {
                            historyRow(device)
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: Theme.Spacing.l, bottom: 3, trailing: Theme.Spacing.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation(Theme.Motion.listItem) {
                                    app.repository.remove(device)
                                }
                            } label: {
                                Label("Forget", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search history")
            }
        }
    }

    private var favoritesList: some View {
        Group {
            if app.repository.favorites.isEmpty {
                EmptyStateView(
                    title: "No favorites",
                    message: "Swipe right on a device, or tap the star on its detail page, to pin it here.",
                    systemImage: "star"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.repository.favorites) { device in
                        NavigationLink(value: device) {
                            DeviceCardRow(device: device)
                                .cardSurface(padding: Theme.Spacing.m)
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: Theme.Spacing.l, bottom: 3, trailing: Theme.Spacing.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button {
                                Haptics.light()
                                withAnimation(Theme.Motion.listItem) {
                                    app.repository.toggleFavorite(device)
                                }
                            } label: {
                                Label("Unfavorite", systemImage: "star.slash")
                            }
                            .tint(Theme.Colors.amber)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Rows

    private func eventRow(_ event: NetworkEvent) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: event.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint(for: event.kind))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                Text("\(event.kind.title) · \(Formatters.time.string(from: event.timestamp))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: Theme.Spacing.l, bottom: 2, trailing: Theme.Spacing.l))
    }

    private func historyRow(_ device: Device) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            DeviceIcon(kind: device.kind, size: 38, isOnline: device.isOnline)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if device.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.amber)
                    }
                }

                Text("\(device.ipAddress) · seen \(device.timesSeen)×")
                    .font(.technical(11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.relativeString(from: device.lastSeen))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                StatusDot(isOnline: device.isOnline, size: 6)
            }
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: 1)
        )
    }

    // MARK: - Derived

    private struct EventGroup {
        var key: String
        var events: [NetworkEvent]
    }

    /// Buckets events by calendar day, newest first.
    private var groupedEvents: [EventGroup] {
        var groups: [EventGroup] = []
        var currentKey: String?

        for event in app.repository.events {
            let key = dayLabel(for: event.timestamp)
            if key != currentKey {
                groups.append(EventGroup(key: key, events: [event]))
                currentKey = key
            } else {
                groups[groups.count - 1].events.append(event)
            }
        }
        return groups
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        return Formatters.shortDate.string(from: date).uppercased()
    }

    private var filteredHistory: [Device] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return app.repository.history }

        return app.repository.history.filter { device in
            device.displayName.lowercased().contains(query)
                || device.ipAddress.description.contains(query)
                || device.vendor?.lowercased().contains(query) == true
                || device.macAddress?.lowercased().contains(query) == true
        }
    }

    private func tint(for kind: NetworkEvent.Kind) -> Color {
        switch kind {
        case .deviceAppeared: Theme.Colors.online
        case .deviceDisappeared: Theme.Colors.offline
        case .deviceReturned: Theme.Colors.accent
        case .networkChanged: Theme.Colors.violet
        case .scanCompleted: Theme.Colors.mint
        case .scanFailed: Theme.Colors.danger
        }
    }
}

#Preview {
    ActivityView()
        .environment(AppEnvironment.preview())
}

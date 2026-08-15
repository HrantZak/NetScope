import SwiftUI

/// Device-type filter plus quick access to sorting and grouping.
struct FilterSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    typeSection
                    statusSection
                    arrangementSection
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.canvas.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        Haptics.light()
                        withAnimation(Theme.Motion.snappy) {
                            app.settings.browse.kindFilter = []
                            app.settings.browse.statusFilter = .all
                        }
                    }
                    .disabled(!app.settings.browse.hasActiveFilters)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(
                "Device type",
                subtitle: app.settings.browse.kindFilter.isEmpty
                    ? "Showing every type"
                    : "\(app.settings.browse.kindFilter.count) selected",
                systemImage: "square.grid.2x2"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: Theme.Spacing.s)],
                spacing: Theme.Spacing.s
            ) {
                ForEach(DeviceKind.allCases) { kind in
                    let isSelected = app.settings.browse.kindFilter.contains(kind)
                    let count = app.repository.devices.lazy.filter { $0.kind == kind }.count

                    Button {
                        Haptics.selection()
                        withAnimation(Theme.Motion.snappy) { toggle(kind) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : Theme.Colors.kind(kind))

                            Text(kind.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .fill(isSelected
                                      ? AnyShapeStyle(Theme.Gradients.kind(kind))
                                      : AnyShapeStyle(Theme.Colors.surface))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : Theme.Colors.hairline, lineWidth: 1)
                        )
                        .opacity(count == 0 && !isSelected ? 0.45 : 1)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Status", systemImage: "circle.dashed")

            Picker("Status", selection: Binding(
                get: { app.settings.browse.statusFilter },
                set: { newValue in
                    Haptics.selection()
                    withAnimation(Theme.Motion.snappy) { app.settings.browse.statusFilter = newValue }
                }
            )) {
                ForEach(BrowsePreferences.StatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var arrangementSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Arrangement", systemImage: "arrow.up.arrow.down")

            VStack(spacing: 0) {
                Picker("Sort by", selection: Binding(
                    get: { app.settings.browse.sortField },
                    set: { app.settings.browse.sortField = $0 }
                )) {
                    ForEach(BrowsePreferences.SortField.allCases) { field in
                        Label(field.title, systemImage: field.symbolName).tag(field)
                    }
                }

                Divider()

                Toggle("Ascending", isOn: Binding(
                    get: { app.settings.browse.sortAscending },
                    set: { app.settings.browse.sortAscending = $0 }
                ))
                .padding(.vertical, 4)

                Divider()

                Picker("Group by", selection: Binding(
                    get: { app.settings.browse.group },
                    set: { app.settings.browse.group = $0 }
                )) {
                    ForEach(BrowsePreferences.GroupField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }

                Divider()

                Picker("Layout", selection: Binding(
                    get: { app.settings.browse.layout },
                    set: { app.settings.browse.layout = $0 }
                )) {
                    ForEach(BrowsePreferences.LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: 1)
            )
        }
    }

    private func toggle(_ kind: DeviceKind) {
        if app.settings.browse.kindFilter.contains(kind) {
            app.settings.browse.kindFilter.remove(kind)
        } else {
            app.settings.browse.kindFilter.insert(kind)
        }
    }
}

#Preview {
    FilterSheet()
        .environment(AppEnvironment.preview())
}

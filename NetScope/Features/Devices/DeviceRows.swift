import SwiftUI

// MARK: - Comfortable card row

/// Default presentation: icon, names, latency and a preview of open services.
///
/// The favourite star is an indicator, not a button: a nested button inside a
/// `NavigationLink` label swallows its own taps in a `List`, so toggling is
/// offered through the leading swipe action, the context menu and the detail
/// screen instead of a control that would only look tappable.
struct DeviceCardRow: View {
    var device: Device

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Capsule()
                .fill(device.isOnline ? Theme.Colors.kind(device.kind) : Theme.Colors.offline)
                .frame(width: 3, height: 48)

            DeviceIcon(kind: device.kind, size: 46, isOnline: device.isOnline)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    if device.isGateway {
                        TagPill(text: "Gateway", systemImage: "arrow.triangle.branch", color: Theme.Colors.accent)
                    }
                    if device.isLocalDevice {
                        TagPill(text: "This device", systemImage: "iphone", color: Theme.Colors.mint)
                    }
                }

                HStack(spacing: 6) {
                    StatusDot(isOnline: device.isOnline, size: 6)
                    Text(device.subtitle)
                        .font(.technical(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Image(systemName: device.discoveryMethod.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityLabel("Found via \(device.discoveryMethod.title)")
                }

                if !device.services.isEmpty {
                    ServicePreviewRow(services: device.services)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 8) {
                LatencyBadge(milliseconds: device.latencyMilliseconds)

                Text(device.kind.title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.45)
                    .foregroundStyle(Theme.Colors.kind(device.kind))
                    .lineLimit(1)

                if device.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.amber)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Up to three service chips plus an overflow counter.
private struct ServicePreviewRow: View {
    var services: [ServiceInfo]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(services.prefix(3)) { service in
                TagPill(
                    text: service.displayName,
                    systemImage: service.symbolName,
                    color: Theme.Colors.violet
                )
            }
            if services.count > 3 {
                TagPill(text: "+\(services.count - 3)", color: Theme.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Compact row

/// Dense one-line row for scanning long lists quickly.
struct DeviceCompactRow: View {
    var device: Device

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: device.kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.kind(device.kind))
                .frame(width: 24)

            Text(device.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)

            if device.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.amber)
            }

            Spacer(minLength: Theme.Spacing.s)

            Text(device.ipAddress.description)
                .font(.technical(12))
                .foregroundStyle(Theme.Colors.textSecondary)

            LatencyBadge(milliseconds: device.latencyMilliseconds, compact: true)

            StatusDot(isOnline: device.isOnline, size: 6)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grid card

struct DeviceGridCard: View {
    var device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                DeviceIcon(kind: device.kind, size: 38, isOnline: device.isOnline)
                Spacer(minLength: 0)
                if device.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.amber)
                }
                StatusDot(isOnline: device.isOnline, size: 7)
            }

            Text(device.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(device.ipAddress.description)
                .font(.technical(11))
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: 6) {
                LatencyBadge(milliseconds: device.latencyMilliseconds, compact: true)
                if !device.services.isEmpty {
                    TagPill(
                        text: "\(device.services.count) svc",
                        systemImage: "bolt.horizontal",
                        color: Theme.Colors.violet
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .cardSurface(cornerRadius: Theme.Radius.medium, padding: Theme.Spacing.m, isHighlighted: device.isGateway)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Table row

/// Column layout mirroring the header in `DeviceTableHeader`.
struct DeviceTableRow: View {
    var device: Device

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(device.ipAddress.description)
                .font(.technical(12, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 108, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: device.kind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.kind(device.kind))
                Text(device.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Formatters.latency(device.latencyMilliseconds))
                .font(.technical(11))
                .foregroundStyle(Theme.Colors.latency(device.latencyMilliseconds))
                .frame(width: 62, alignment: .trailing)

            Text("\(device.services.count)")
                .font(.technical(11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 30, alignment: .trailing)

            StatusDot(isOnline: device.isOnline, size: 6)
                .frame(width: 14)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DeviceTableHeader: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("IP ADDRESS").frame(width: 108, alignment: .leading)
            Text("DEVICE").frame(maxWidth: .infinity, alignment: .leading)
            Text("RTT").frame(width: 62, alignment: .trailing)
            Text("SVC").frame(width: 30, alignment: .trailing)
            Text("").frame(width: 14)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.vertical, 6)
    }
}

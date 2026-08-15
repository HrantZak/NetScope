import SwiftUI

// MARK: - Device icon

/// Rounded gradient tile with the device-type glyph.
struct DeviceIcon: View {
    var kind: DeviceKind
    var size: CGFloat = 44
    var isOnline: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Theme.Gradients.kind(kind))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
            }
            .saturation(isOnline ? 1 : 0.15)
            .opacity(isOnline ? 1 : 0.7)
            .shadow(color: Theme.Colors.kind(kind).opacity(isOnline ? 0.35 : 0), radius: 8, y: 4)
    }
}

// MARK: - Status

/// Online indicator with a slow pulse. The pulse is skipped when the system
/// asks for reduced motion, and for offline devices where it means nothing.
struct StatusDot: View {
    var isOnline: Bool
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(isOnline ? Theme.Colors.online : Theme.Colors.offline)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Theme.Colors.online.opacity(0.5), lineWidth: 2)
                    .scaleEffect(isPulsing ? 2.2 : 1)
                    .opacity(isPulsing ? 0 : 0.8)
            }
            .onAppear {
                guard isOnline, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
            .accessibilityLabel(isOnline ? "Online" : "Offline")
    }
}

/// Colour-coded round-trip time.
struct LatencyBadge: View {
    var milliseconds: Double?
    var compact: Bool = false

    var body: some View {
        let color = Theme.Colors.latency(milliseconds)

        HStack(spacing: 4) {
            if !compact {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(milliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                .font(.technical(compact ? 11 : 12, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            Capsule().fill(color.opacity(0.14))
        )
        .accessibilityLabel(milliseconds.map { "Latency \(Int($0)) milliseconds" } ?? "Latency unknown")
    }
}

// MARK: - Pills and chips

/// Small labelled pill used for services, tags and metadata.
struct TagPill: View {
    var text: String
    var systemImage: String?
    var color: Color = Theme.Colors.accent
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? .white : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)))
        )
    }
}

/// Selectable chip used by the filter bar.
struct FilterChip: View {
    var title: String
    var systemImage: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(Theme.Gradients.accent) : AnyShapeStyle(Theme.Colors.surface))
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.Colors.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Metric tile

/// Compact KPI tile used across the dashboard and statistics screens.
struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = Theme.Colors.accent
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.metric(26, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.medium, padding: Theme.Spacing.m)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var accessory: AnyView?

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        accessory: AnyView? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if let accessory { accessory }
        }
    }
}

// MARK: - Key/value row

/// Label on the left, selectable technical value on the right.
struct DetailRow: View {
    var label: String
    var value: String?
    var systemImage: String?
    var isMonospaced: Bool = true
    var tint: Color = Theme.Colors.textPrimary

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 18)
            }

            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer(minLength: Theme.Spacing.m)

            Text(value ?? "Unavailable")
                .font(isMonospaced ? .technical(13, weight: .medium) : .system(size: 14, weight: .medium))
                .foregroundStyle(value == nil ? Theme.Colors.textTertiary : tint)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Progress

/// Thin gradient progress bar with an indeterminate shimmer mode.
struct ScanProgressBar: View {
    var fraction: Double
    var isIndeterminate: Bool = false

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.surfaceSunken)

                if isIndeterminate {
                    Capsule()
                        .fill(Theme.Gradients.accent)
                        .frame(width: width * 0.35)
                        .offset(x: shimmerOffset * width)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                                shimmerOffset = 1
                            }
                        }
                } else {
                    Capsule()
                        .fill(Theme.Gradients.accent)
                        .frame(width: max(width * fraction, fraction > 0 ? 6 : 0))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .animation(Theme.Motion.smooth, value: fraction)
    }
}

/// Circular progress used by the scan hero card.
struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 8
    var tint: LinearGradient = Theme.Gradients.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surfaceSunken, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.smooth, value: fraction)
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.Gradients.accent)
            }

            VStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primaryCapsule)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 420)
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search devices, IP, vendor…"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFocused ? Theme.Colors.accent : Theme.Colors.textTertiary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .foregroundStyle(Theme.Colors.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(isFocused ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.hairline, lineWidth: 1)
        )
        .animation(Theme.Motion.quick, value: isFocused)
        .animation(Theme.Motion.quick, value: text.isEmpty)
    }
}

// MARK: - Button styles

/// Scales and dims slightly while pressed. Applied to every custom control so
/// touch feedback is consistent app-wide.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    var tint: LinearGradient = Theme.Gradients.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.m)
            .background(Capsule().fill(tint))
            .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == PrimaryCapsuleButtonStyle {
    static var primaryCapsule: PrimaryCapsuleButtonStyle { PrimaryCapsuleButtonStyle() }
}

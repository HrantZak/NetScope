import SwiftUI
import UIKit

/// Design tokens for the whole app.
///
/// Colours are declared as light/dark pairs and resolved through `UIColor`'s
/// trait-aware initialiser, so every surface adapts automatically and no view
/// has to read `@Environment(\.colorScheme)` just to pick a shade.
enum Theme {

    // MARK: - Colour

    enum Colors {
        /// Primary brand colour. Matches the `AccentColor` asset.
        static let accent = Color.adaptive(light: 0x2E84FC, dark: 0x4C9DFF)
        static let accentSoft = Color.adaptive(light: 0xE8F1FF, dark: 0x16243D)

        static let mint = Color.adaptive(light: 0x00B27A, dark: 0x30E3A0)
        static let violet = Color.adaptive(light: 0x7C5CFF, dark: 0xA78BFA)
        static let amber = Color.adaptive(light: 0xE08700, dark: 0xFFB340)
        static let rose = Color.adaptive(light: 0xE0335B, dark: 0xFF6B8A)

        /// Page background, painted behind the aurora.
        static let canvas = Color.adaptive(light: 0xF3F5FA, dark: 0x08090D)

        /// Card / row fill. A solid colour rather than a material: rows are
        /// recycled by the thousand and blur is expensive to composite.
        static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x14161C)
        static let surfaceElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1B1E26)
        static let surfaceSunken = Color.adaptive(light: 0xEDF0F6, dark: 0x0E1015)

        static let hairline = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)

        static let textPrimary = Color.adaptive(light: 0x0B1020, dark: 0xF5F7FB)
        static let textSecondary = Color.adaptive(light: 0x5A6376, dark: 0x9AA3B5)
        static let textTertiary = Color.adaptive(light: 0x8A93A6, dark: 0x6B7385)

        static let online = Color.adaptive(light: 0x1DA362, dark: 0x32D583)
        static let offline = Color.adaptive(light: 0x98A1B2, dark: 0x5B6373)
        static let warning = Color.adaptive(light: 0xD97706, dark: 0xFDB022)
        static let danger = Color.adaptive(light: 0xD92D20, dark: 0xF97066)

        /// Colour used for a device category, keeping icons recognisable.
        static func kind(_ kind: DeviceKind) -> Color {
            switch kind {
            case .router: accent
            case .computer: violet
            case .phone: mint
            case .tablet: mint
            case .wearable: rose
            case .tv: violet
            case .speaker: amber
            case .printer: Color.adaptive(light: 0x0E7490, dark: 0x22D3EE)
            case .camera: rose
            case .storage: Color.adaptive(light: 0x9333EA, dark: 0xC084FC)
            case .console: Color.adaptive(light: 0x2563EB, dark: 0x60A5FA)
            case .iot: amber
            case .server: Color.adaptive(light: 0x0F766E, dark: 0x2DD4BF)
            case .unknown: Color.adaptive(light: 0x64748B, dark: 0x94A3B8)
            }
        }

        /// Green through red, driven by round-trip time.
        static func latency(_ milliseconds: Double?) -> Color {
            guard let milliseconds else { return offline }
            switch milliseconds {
            case ..<15: return online
            case ..<60: return mint
            case ..<200: return warning
            default: return danger
            }
        }
    }

    // MARK: - Gradients

    enum Gradients {
        static let accent = LinearGradient(
            colors: [Colors.accent, Colors.violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let success = LinearGradient(
            colors: [Colors.mint, Colors.accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Subtle top-light edge that sells the glass effect.
        static var glassStroke: LinearGradient {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.55),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static func kind(_ kind: DeviceKind) -> LinearGradient {
            let base = Colors.kind(kind)
            return LinearGradient(
                colors: [base, base.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Metrics

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 22
        static let extraLarge: CGFloat = 30
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 32
    }

    // MARK: - Motion

    /// Shared animation curves. Using named constants keeps timing consistent
    /// and makes it trivial to slow everything down when debugging.
    enum Motion {
        static let snappy = Animation.snappy(duration: 0.32, extraBounce: 0.04)
        static let smooth = Animation.smooth(duration: 0.42)
        static let quick = Animation.easeOut(duration: 0.18)
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
        static let listItem = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }
}

// MARK: - Colour helpers

extension Color {

    /// Builds a colour that resolves differently per interface style.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

extension Font {
    /// Rounded numerals for metrics — reads better than the default in tiles.
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced digits keep addresses and latencies from jittering as they
    /// update in place.
    static func technical(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

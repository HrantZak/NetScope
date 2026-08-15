import SwiftUI

// MARK: - Card surfaces

/// Solid card used for list rows and dense content.
///
/// Deliberately *not* a material: `List`/`LazyVStack` rows are composited on
/// every frame while scrolling, and blurring each one is the single easiest way
/// to drop frames on a long device list.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.large
    var padding: CGFloat = Theme.Spacing.l
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Theme.Colors.accent.opacity(0.45) : Theme.Colors.hairline,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

/// Frosted glass surface for floating chrome: toolbars, sheets, overlays.
///
/// Reserved for a handful of always-on-screen elements, where one blur layer
/// costs nothing and the depth is worth it.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.extraLarge
    var padding: CGFloat = Theme.Spacing.l
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Gradients.glassStroke, lineWidth: 1)
                    .blendMode(.overlay)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
    }
}

extension View {
    func cardSurface(
        cornerRadius: CGFloat = Theme.Radius.large,
        padding: CGFloat = Theme.Spacing.l,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius, padding: padding, isHighlighted: isHighlighted))
    }

    func glassSurface(
        cornerRadius: CGFloat = Theme.Radius.extraLarge,
        padding: CGFloat = Theme.Spacing.l,
        tint: Color = .clear
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, padding: padding, tint: tint))
    }
}

// MARK: - Background

/// Slow-moving ambient gradient behind every screen.
///
/// Rendered once as a static composite of blurred ellipses and animated with a
/// long, low-frequency phase: no per-frame layout, no `TimelineView`, and it
/// stops entirely when the app is not active.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Theme.Colors.canvas

                blob(
                    color: Theme.Colors.accent.opacity(0.30),
                    diameter: size.width * 1.05,
                    offset: CGSize(
                        width: -size.width * 0.32 + phase * 26,
                        height: -size.height * 0.28 - phase * 18
                    )
                )

                blob(
                    color: Theme.Colors.violet.opacity(0.24),
                    diameter: size.width * 0.95,
                    offset: CGSize(
                        width: size.width * 0.36 - phase * 20,
                        height: -size.height * 0.10 + phase * 24
                    )
                )

                blob(
                    color: Theme.Colors.mint.opacity(0.18),
                    diameter: size.width * 0.85,
                    offset: CGSize(
                        width: size.width * 0.08 + phase * 16,
                        height: size.height * 0.34 - phase * 12
                    )
                )
            }
            .ignoresSafeArea()
            .onAppear(perform: startAnimating)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { startAnimating() }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(color: Color, diameter: CGFloat, offset: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.28)
            .offset(offset)
    }

    private func startAnimating() {
        guard !reduceMotion, phase == 0 else { return }
        withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
            phase = 1
        }
    }
}

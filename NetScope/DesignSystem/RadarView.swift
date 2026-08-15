import SwiftUI

/// Animated radar shown while a scan is running.
///
/// Drawn entirely in a single `Canvas`, and the `TimelineView` that drives the
/// sweep only exists while `isActive` is true — an idle radar costs zero frames.
struct RadarView: View {
    var isActive: Bool
    var blipCount: Int
    var tint: Color = Theme.Colors.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isActive && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
                    let angle = sweepAngle(at: context.date)
                    canvas(sweep: angle)
                }
            } else {
                canvas(sweep: isActive ? .degrees(45) : nil)
            }
        }
        .accessibilityHidden(true)
    }

    private func sweepAngle(at date: Date) -> Angle {
        let period: Double = 2.4
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return .degrees(phase * 360)
    }

    private func canvas(sweep: Angle?) -> some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2

            // Concentric range rings.
            for step in 1...4 {
                let radius = maxRadius * CGFloat(step) / 4
                let ring = Path(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(
                    ring,
                    with: .color(tint.opacity(0.10 + 0.05 * Double(4 - step))),
                    lineWidth: step == 4 ? 1.2 : 0.8
                )
            }

            // Cross hairs.
            var crossHairs = Path()
            crossHairs.move(to: CGPoint(x: centre.x - maxRadius, y: centre.y))
            crossHairs.addLine(to: CGPoint(x: centre.x + maxRadius, y: centre.y))
            crossHairs.move(to: CGPoint(x: centre.x, y: centre.y - maxRadius))
            crossHairs.addLine(to: CGPoint(x: centre.x, y: centre.y + maxRadius))
            context.stroke(crossHairs, with: .color(tint.opacity(0.10)), lineWidth: 0.8)

            // Sweeping wedge with a fading tail.
            if let sweep {
                var wedge = Path()
                wedge.move(to: centre)
                wedge.addArc(
                    center: centre,
                    radius: maxRadius,
                    startAngle: sweep - .degrees(38),
                    endAngle: sweep,
                    clockwise: false
                )
                wedge.closeSubpath()

                context.fill(
                    wedge,
                    with: .radialGradient(
                        Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                        center: centre,
                        startRadius: 0,
                        endRadius: maxRadius
                    )
                )

                var leadingEdge = Path()
                leadingEdge.move(to: centre)
                leadingEdge.addLine(to: CGPoint(
                    x: centre.x + cos(sweep.radians) * maxRadius,
                    y: centre.y + sin(sweep.radians) * maxRadius
                ))
                context.stroke(leadingEdge, with: .color(tint.opacity(0.8)), lineWidth: 1.5)
            }

            // Blips: deterministic pseudo-random placement so they stay put
            // between frames instead of jittering.
            let visibleBlips = min(blipCount, 40)
            guard visibleBlips > 0 else { return }

            for index in 0..<visibleBlips {
                let seed = Double(index)
                let angle = (seed * 137.508).truncatingRemainder(dividingBy: 360) * .pi / 180
                let distance = maxRadius * (0.22 + 0.68 * ((seed * 0.618).truncatingRemainder(dividingBy: 1)))
                let point = CGPoint(
                    x: centre.x + cos(angle) * distance,
                    y: centre.y + sin(angle) * distance
                )
                let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                context.fill(dot, with: .color(tint.opacity(0.9)))
                let halo = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
                context.fill(halo, with: .color(tint.opacity(0.18)))
            }
        }
    }
}

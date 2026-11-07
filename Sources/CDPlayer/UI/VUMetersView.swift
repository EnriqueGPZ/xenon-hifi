import CDPlayerKit
import SwiftUI

/// Two analog VU meters across the display, left and right channel: a
/// black face lit from behind, a gold scale turning red above 0, and a pale
/// needle swinging from a pivot below the face.
struct VUMetersView: View {
    let meters: VUMeters

    var body: some View {
        HStack(spacing: Space.xs) {
            VUFace(position: meters.left, channel: "L")
            VUFace(position: meters.right, channel: "R")
        }
        .accessibilityElement()
        .accessibilityLabel("Vúmetros")
    }
}

/// The shared geometry of a meter face: a pivot below the face and the
/// scale arc around it.
nonisolated private struct VUGeometry {
    let size: CGSize
    let swing: Double
    var pivot: CGPoint { CGPoint(x: size.width / 2, y: size.height * 1.42) }
    var radius: CGFloat { size.height * 1.12 }

    /// The angle for a scale place (0 left stop, 1 right stop), in radians
    /// from straight up.
    func angle(_ place: Double) -> Double { (place * 2 - 1) * swing * .pi / 180 }

    func point(_ place: Double, _ distance: CGFloat) -> CGPoint {
        let a = angle(place)
        return CGPoint(x: pivot.x + distance * sin(a), y: pivot.y - distance * cos(a))
    }

    func arc(from: Double, to: Double, at distance: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: pivot, radius: distance, startAngle: .radians(angle(from) - .pi / 2),
                    endAngle: .radians(angle(to) - .pi / 2), clockwise: false)
        return path
    }
}

/// One meter: the printed face, drawn once, and the needle on top, the only
/// part redrawn as the sound moves.
private struct VUFace: View {
    let position: Double
    let channel: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlayerTokens.vuRadius, style: .continuous)
        VUScale(channel: channel)
            .overlay { VUNeedle(position: position) }
            .background {
                shape.fill(LinearGradient(colors: [PlayerTokens.vuFaceTop, PlayerTokens.vuFaceBottom],
                                          startPoint: .top, endPoint: .bottom))
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.black, lineWidth: 1) }
    }
}

private struct VUNeedle: View {
    let position: Double

    var body: some View {
        Canvas { context, size in
            let geometry = VUGeometry(size: size, swing: PlayerTokens.vuSwing)
            var needle = Path()
            needle.move(to: geometry.point(position, geometry.radius * 0.35))
            needle.addLine(to: geometry.point(position, geometry.radius + 5))
            context.stroke(needle.offsetBy(dx: 1, dy: 1), with: .color(PlayerTokens.vuNeedleShadow),
                           lineWidth: PlayerTokens.vuNeedleWidth)
            context.stroke(needle, with: .color(PlayerTokens.vuNeedle),
                           style: StrokeStyle(lineWidth: PlayerTokens.vuNeedleWidth, lineCap: .round))
        }
    }
}

/// The printed part of the face: lamp, scale, marks, numbers, "VU".
private struct VUScale: View {
    let channel: String

    var body: some View {
        Canvas { context, size in
            let geometry = VUGeometry(size: size, swing: PlayerTokens.vuSwing)
            func point(_ place: Double, _ distance: CGFloat) -> CGPoint { geometry.point(place, distance) }
            func arc(from: Double, to: Double, at distance: CGFloat) -> Path { geometry.arc(from: from, to: to, at: distance) }
            // The lamp behind the scale.
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [PlayerTokens.vuLamp, .clear]),
                                               center: CGPoint(x: size.width / 2, y: size.height * 0.55),
                                               startRadius: 0, endRadius: size.width * 0.55))

            let red = VUMeter.place(vu: VUMeter.redFrom)
            // A thin line for the scale and a broad band under it, gold then red.
            let line = geometry.radius, band = geometry.radius - 4.5
            context.stroke(arc(from: 0, to: red, at: line), with: .color(PlayerTokens.vuScale), lineWidth: PlayerTokens.vuLine)
            context.stroke(arc(from: red, to: 1, at: line), with: .color(PlayerTokens.vuRed), lineWidth: PlayerTokens.vuLine)
            context.stroke(arc(from: 0, to: red, at: band), with: .color(PlayerTokens.vuScale), lineWidth: PlayerTokens.vuBand)
            context.stroke(arc(from: red, to: 1, at: band), with: .color(PlayerTokens.vuRed), lineWidth: PlayerTokens.vuBand)

            // Marks and numbers: big ones on the printed values, small ones between.
            for mark in VUMeter.marks {
                let at = VUMeter.place(vu: mark)
                let color = mark > VUMeter.redFrom ? PlayerTokens.vuRed : PlayerTokens.vuScale
                var tick = Path()
                tick.move(to: point(at, line))
                tick.addLine(to: point(at, line + 4))
                context.stroke(tick, with: .color(color), lineWidth: PlayerTokens.vuTick)
                let number = mark == 0 ? "0" : String(Int(abs(mark)))
                context.draw(Text(number).font(PlayerTokens.vuNumberFont).foregroundStyle(color),
                             at: point(at, line + 9.5))
            }
            for minor in stride(from: -19.0, through: -11, by: 2) {
                var tick = Path()
                tick.move(to: point(VUMeter.place(vu: minor), line))
                tick.addLine(to: point(VUMeter.place(vu: minor), line + 2))
                context.stroke(tick, with: .color(PlayerTokens.vuScale), lineWidth: PlayerTokens.vuTickMinor)
            }
            context.draw(Text("−").font(PlayerTokens.vuNumberFont).foregroundStyle(PlayerTokens.vuScale),
                         at: point(-0.035, line + 9.5))
            context.draw(Text("+").font(PlayerTokens.vuNumberFont).foregroundStyle(PlayerTokens.vuRed),
                         at: point(1.035, line + 9.5))

            context.draw(Text("VU").font(PlayerTokens.vuNameFont).foregroundStyle(PlayerTokens.vuScale),
                         at: CGPoint(x: size.width / 2, y: size.height * 0.66))
            context.draw(Text(channel).font(PlayerTokens.vuChannelFont).foregroundStyle(PlayerTokens.vuScale.opacity(0.7)),
                         at: CGPoint(x: size.width - 9, y: size.height - 8))

        }
        .drawingGroup()
    }
}

import CDPlayerKit
import SwiftUI

/// The face of a Denon-style button or knob: spun aluminium with fine
/// concentric rings, the bright cross-shaped sheen that spun metal throws
/// back, a chamfered rim, all set in a dark collar cut into the front.
struct SpunMetalFace: View {
    let size: CGFloat
    var pressed = false

    var body: some View {
        ZStack {
            // The hole in the front panel the button sits in.
            Circle()
                .fill(LinearGradient(colors: [PlayerTokens.collarTop, PlayerTokens.collarBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size + 2 * PlayerTokens.collarWidth, height: size + 2 * PlayerTokens.collarWidth)
            face
                .frame(width: size, height: size)
                .scaleEffect(pressed ? 0.97 : 1)
                .shadow(color: .black.opacity(pressed ? 0.3 : 0.7), radius: pressed ? 1 : 2, y: pressed ? 0 : 1)
        }
        .accessibilityHidden(true)
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [PlayerTokens.buttonFaceLight, PlayerTokens.buttonFaceDark],
                                     center: .center, startRadius: 0, endRadius: size * 0.6))
            // The sheen: two bright lobes across the diagonal, two faint ones.
            Circle()
                .fill(AngularGradient(stops: [
                    .init(color: .white.opacity(0.0), location: 0.00),
                    .init(color: .white.opacity(0.55), location: 0.125),
                    .init(color: .white.opacity(0.0), location: 0.25),
                    .init(color: .white.opacity(0.14), location: 0.375),
                    .init(color: .white.opacity(0.0), location: 0.50),
                    .init(color: .white.opacity(0.45), location: 0.625),
                    .init(color: .white.opacity(0.0), location: 0.75),
                    .init(color: .white.opacity(0.12), location: 0.875),
                    .init(color: .white.opacity(0.0), location: 1.00),
                ], center: .center, angle: .zero))
                .blendMode(.screen)
            SpunRings()
            // A soft dimple in the middle, where the lathe started.
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.12))
            Circle()
                .strokeBorder(AngularGradient(colors: [PlayerTokens.buttonRimLight, .black.opacity(0.8),
                                                       PlayerTokens.buttonRimLight, .black.opacity(0.8),
                                                       PlayerTokens.buttonRimLight],
                                              center: .center, angle: .zero), lineWidth: 1.5) // grid: ok chamfer line, not spacing
            if pressed {
                Circle().fill(PlayerTokens.buttonPressed)
            }
        }
        .compositingGroup()
    }
}

/// The fine rings a lathe leaves on spun metal.
private struct SpunRings: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var radius: CGFloat = 1
            var ring = 0
            while radius < size.width / 2 {
                let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
                let alpha = ring % 3 == 0 ? 0.07 : 0.025
                context.stroke(path, with: .color(ring % 2 == 0 ? .black.opacity(alpha) : .white.opacity(alpha)),
                               lineWidth: 0.5) // grid: ok lathe ring hairline
                radius += 0.75
                ring += 1
            }
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

/// A round metal button. Like on a Denon, its symbol or name is printed on
/// the front above it, not on the button itself.
struct RoundButton: View {
    let help: String
    var size: CGFloat = PlayerTokens.buttonMedium
    /// Keeps firing while held, for fast-forward and rewind.
    var repeats = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Color.clear }
            .buttonStyle(MetalButtonStyle(size: size))
            .buttonRepeatBehavior(repeats ? .enabled : .disabled)
            .help(help)
            .accessibilityLabel(help)
    }
}

private struct MetalButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        SpunMetalFace(size: size, pressed: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// A round button that does one thing when clicked and another, again and
/// again, while held: |<< and >>| that scan back and forward through the
/// song, as on a CD player.
struct HoldButton: View {
    let help: String
    var size: CGFloat = PlayerTokens.buttonSmall
    let tap: () -> Void
    let hold: () -> Void
    @State private var pressed = false
    @State private var held = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        SpunMetalFace(size: size, pressed: pressed)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    held = false
                    repeater = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(PlayerTokens.holdDelay))
                        while !Task.isCancelled {
                            held = true
                            hold()
                            try? await Task.sleep(for: .seconds(PlayerTokens.holdRepeat))
                        }
                    }
                }
                .onEnded { _ in
                    repeater?.cancel()
                    repeater = nil
                    pressed = false
                    if !held { tap() }
                })
            .help(help)
            .accessibilityElement()
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap() }
    }
}

/// Symbols printed on the panel above a button, like "▶/II" on the reference.
struct PrintedSymbols: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                if index > 0 {
                    Text("/").font(PlayerTokens.printFont)
                }
                Image(systemName: symbol).font(PlayerTokens.printFont)
            }
        }
        .foregroundStyle(PlayerTokens.engraved)
        .frame(height: Space.md)
        .accessibilityHidden(true)
    }
}

/// A transport button with its symbols printed above it.
struct TransportButton: View {
    let symbols: [String]
    let help: String
    var repeats = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: Space.sm) {
            PrintedSymbols(symbols: symbols)
            RoundButton(help: help, repeats: repeats, action: action)
        }
    }
}

/// A small mode button with its name printed above it and a pilot light
/// next to the name that glows while the mode is on.
struct LabeledButton: View {
    let label: String
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                ModeLight(on: active)
                EngravedLabel(text: label)
            }
            RoundButton(help: help, size: PlayerTokens.buttonSmall, action: action)
        }
    }
}

/// The tiny light beside a mode's name.
struct ModeLight: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? PlayerTokens.modeLightOn : PlayerTokens.modeLightOff)
            .frame(width: PlayerTokens.modeLightSize, height: PlayerTokens.modeLightSize)
            .shadow(color: on ? PlayerTokens.modeLightGlow : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

struct EngravedLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PlayerTokens.labelFont)
            .tracking(1)
            .foregroundStyle(PlayerTokens.engraved)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The power LED: lit while the player is on.
struct PowerLED: View {
    var body: some View {
        Circle()
            .fill(PlayerTokens.ledOn)
            .frame(width: PlayerTokens.ledSize, height: PlayerTokens.ledSize)
            .shadow(color: PlayerTokens.ledGlow, radius: 3)
            .accessibilityHidden(true)
    }
}

/// A rotary knob in spun metal, with a printed scale around it. Drag up or
/// down (or sideways), or use the arrow keys when it has focus. `value`
/// runs 0...1 from the left stop to the right stop.
struct RotaryKnob: View {
    let value: Double
    var size: CGFloat = PlayerTokens.knobSize
    /// Marks the middle of the scale, for knobs that rest at the centre.
    var centreMark = false
    let help: String
    let accessibilityName: String
    let accessibilityText: String
    /// Sets a new value while dragging, 0...1.
    let set: (Double) -> Void
    /// One step up (+1) or down (-1), from the keys.
    let nudge: (Int) -> Void
    var reset: (() -> Void)?
    /// An endless selector with detents instead of a level: every `detent`
    /// points of drag is one click, sent here (+1 clockwise: right or up).
    /// A slow turn moves one row; a faster turn, more rows, one by one.
    var step: ((Int) -> Void)?
    var detent: CGFloat = PlayerTokens.knobDetent

    @State private var dragStart: Double?
    @State private var clicks = 0
    @FocusState private var focused: Bool

    private var angle: Angle {
        .degrees(-135 + value * 270)
    }

    var body: some View {
        ZStack {
            KnobScale(diameter: size + 4 * Space.xs, centreMark: centreMark)
            SpunMetalFace(size: size)
            // The pointer: a small recessed mark that turns with the knob.
            VStack(spacing: 0) {
                Circle()
                    .fill(PlayerTokens.knobIndicator)
                    .frame(width: Space.xs, height: Space.xs)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                Spacer(minLength: 0)
            }
            .padding(.top, size > PlayerTokens.buttonLarge ? Space.sm : Space.xs)
            .frame(width: size, height: size)
            .rotationEffect(angle)
        }
        .frame(width: size + 4 * Space.xs, height: size + 4 * Space.xs)
        .contentShape(Circle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { nudge(1); return .handled }
        .onKeyPress(.rightArrow) { nudge(1); return .handled }
        .onKeyPress(.downArrow) { nudge(-1); return .handled }
        .onKeyPress(.leftArrow) { nudge(-1); return .handled }
        .onTapGesture(count: 2) { reset?() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    focused = true
                    let distance = drag.translation.width - drag.translation.height
                    if let step {
                        let reached = Int((distance / detent).rounded(.towardZero))
                        while clicks != reached {
                            let direction = reached > clicks ? 1 : -1
                            clicks += direction
                            step(direction)
                        }
                        return
                    }
                    if dragStart == nil { dragStart = value }
                    set(min(1, max(0, (dragStart ?? value) + Double(distance) / 160)))
                }
                .onEnded { _ in
                    dragStart = nil
                    clicks = 0
                }
        )
        .help(help)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityText)
        .accessibilityAdjustableAction { direction in nudge(direction == .increment ? 1 : -1) }
    }
}

/// The volume knob. The display shows the level while it turns.
struct VolumeKnob: View {
    let model: AppModel

    var body: some View {
        RotaryKnob(value: model.volume,
                   help: "Volumen: arrastra arriba o abajo",
                   accessibilityName: "Volumen",
                   accessibilityText: "\(Int((model.volume * 100).rounded())) por ciento",
                   set: { model.volume = $0; model.showVolume() },
                   nudge: { model.nudgeVolume(by: 0.05 * Double($0)) })
    }
}

/// The balance knob: left stop all left, right stop all right, clicking
/// into the centre. Double-click puts it back in the middle.
struct BalanceKnob: View {
    let model: AppModel

    var body: some View {
        RotaryKnob(value: (model.balance + 1) / 2, size: PlayerTokens.balanceKnobSize, centreMark: true,
                   help: "Balance: arrastra a izquierda o derecha; doble clic para centrar",
                   accessibilityName: "Balance",
                   accessibilityText: Balance.label(model.balance),
                   set: { model.balance = Balance.clamp($0 * 2 - 1); model.showBalance() },
                   nudge: { model.nudgeBalance(by: Balance.step * Double($0)) },
                   reset: { model.centerBalance() })
    }
}

/// The printed dots around the knob, from minimum to maximum.
private struct KnobScale: View {
    let diameter: CGFloat
    var centreMark = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = diameter / 2 - 2
            for step in 0...10 {
                let degrees = -135 + Double(step) * 27 - 90
                let radians = degrees * .pi / 180
                let big = step == 0 || step == 10 || (centreMark && step == 5)
                let dot: CGFloat = big ? 2.5 : 1.5
                let point = CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2,
                                                    width: dot, height: dot)),
                             with: .color(PlayerTokens.knobTick))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

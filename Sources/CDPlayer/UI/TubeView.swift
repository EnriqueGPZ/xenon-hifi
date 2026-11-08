import CDPlayerKit
import SwiftUI

/// The tube preamp, a hi-fi unit that matches the others: the same brushed
/// front, buttons, knob and feet, with a window cut in the front where four
/// glass tubes stand on their sockets. Their filaments glow amber once warm;
/// with VÁLVULAS on, the glow rises and falls with each channel's sound
/// (the two on the left follow the left channel, the two on the right the
/// right). The sound itself: CDPlayerKit/Tube.swift.
struct TubeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var dragging = false

    private var tube: TubeModel { model.tube }

    var body: some View {
        VStack(spacing: 0) {
            panel
            HStack {
                Foot()
                Spacer()
                Foot()
            }
            .padding(.horizontal, Space.section + Space.xl)
        }
        .padding(Space.lg)
        .noInitialFocus()
        .onAppear {
            tube.startWatching()
            // Once the window has its size: in its place in the stack.
            DispatchQueue.main.async { UnitStack.arrange() }
        }
        .onDisappear {
            tube.stopWatching()
            UnitStack.unitClosed()
        }
    }

    private var panel: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            leftColumn
            TubeWindow(glow: tube.glow)
            rightColumn
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.section + Space.xs)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
        .background { BrushedPanel() }
        // Dragging the unit moves the whole stack (UI/UnitStack.swift).
        .gesture(DragGesture(minimumDistance: 1).onChanged { _ in
            if !dragging { dragging = true; UnitStack.dragStack() }
        }.onEnded { _ in dragging = false })
        .allowsWindowActivationEvents(true)
    }

    /// The brand at the top; the power button at the bottom closes the unit.
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLogo()
            Spacer(minLength: Space.lg)
            VStack(spacing: Space.xs) {
                PowerLED()
                PrintedSymbols(symbols: ["power"])
                RoundButton(help: "Cerrar el previo a válvulas (sigue sonando como está)") {
                    dismissWindow(id: TubeView.windowID)
                }
            }
        }
        .frame(width: 128, alignment: .leading)
    }

    /// The switch with its amber light, the CALIDEZ knob, the model name.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: Space.md) {
            HStack(alignment: .bottom, spacing: Space.xl) {
                VStack(spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        TubeLamp(on: tube.settings.enabled)
                        EngravedLabel(text: "VÁLVULAS")
                    }
                    RoundButton(help: "Encender o apagar las válvulas, para comparar (V)",
                                size: PlayerTokens.buttonMedium) { tube.toggle() }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(tube.settings.enabled ? "encendidas" : "apagadas")
                VStack(spacing: 0) {
                    RotaryKnob(value: tube.settings.warmth,
                               help: "Calidez: cuánto colorean las válvulas el sonido. Doble clic, a la mitad",
                               accessibilityName: "Calidez",
                               accessibilityText: "\(tube.warmthPercent) por ciento",
                               set: { tube.setWarmth($0) },
                               nudge: { tube.nudgeWarmth(by: $0) },
                               reset: { tube.resetWarmth() })
                    EngravedLabel(text: "CALIDEZ")
                }
            }
            crossfeedRow
            Spacer(minLength: 0)
            Text("TUBE PREAMPLIFIER  TP-4")
                .font(PlayerTokens.modelFont)
                .tracking(1)
                .foregroundStyle(PlayerTokens.engravedDim)
        }
        .frame(width: 288)
    }

    /// CROSSFEED for headphones, and its three levels: the light of the
    /// chosen level stays lit, so the selector's position shows even when off.
    private var crossfeedRow: some View {
        HStack(alignment: .bottom, spacing: Space.xl) {
            LabeledButton(label: "CROSSFEED", active: tube.crossfeed.enabled,
                          help: "Crossfeed para auriculares: mezcla un poco de cada canal en el otro, como oyes unos altavoces (C)") {
                tube.toggleCrossfeed()
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(tube.crossfeed.enabled ? "encendido" : "apagado")
            HStack(alignment: .bottom, spacing: Space.md) {
                ForEach(CrossfeedLevel.allCases, id: \.self) { level in
                    LabeledButton(label: level.label, active: tube.crossfeed.level == level,
                                  help: "Crossfeed \(level.label.lowercased()): \(Self.formatted(level.feed)) dB, \(Int(level.cutoff)) Hz (Mayúsculas C cambia de nivel)") {
                        tube.setCrossfeedLevel(level)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(tube.crossfeed.level == level ? "elegido" : "")
                }
            }
        }
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "es_ES")))
    }

    static let windowID = "tubes"
}

/// The amber pilot light beside VÁLVULAS.
private struct TubeLamp: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? PlayerTokens.tubeLampOn : PlayerTokens.modeLightOff)
            .frame(width: PlayerTokens.modeLightSize, height: PlayerTokens.modeLightSize)
            .shadow(color: on ? PlayerTokens.tubeLampGlow : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

// MARK: - The window and its tubes

/// The window cut in the front: a dark chamber, warm light on its back wall
/// and floor, and the four tubes standing in a row.
private struct TubeWindow: View {
    let glow: [Double]

    private let kinds: [TubePicture] = [.small, .large, .large, .small]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlayerTokens.displayRadius, style: .continuous)
        let average = (glow[0] + glow[1]) / 2
        ZStack(alignment: .bottom) {
            shape.fill(LinearGradient(colors: [PlayerTokens.tubeWindowTop, PlayerTokens.tubeWindowBottom],
                                      startPoint: .top, endPoint: .bottom))
            // The warm light the filaments throw on the back wall.
            Ellipse()
                .fill(PlayerTokens.tubeHalo.opacity(0.3 * average))
                .frame(width: PlayerTokens.displayWidth * 0.8, height: PlayerTokens.tubeWindowHeight * 0.7)
                .blur(radius: 28)
                .offset(y: -PlayerTokens.tubeWindowHeight * 0.2) // grid: ok tube drawing detail
            // The chassis floor the tubes stand on.
            Rectangle()
                .fill(PlayerTokens.tubeFloor)
                .frame(height: PlayerTokens.tubeFloorHeight)
                .overlay(alignment: .top) { Rectangle().fill(PlayerTokens.panelHighlight).frame(height: 1) }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(kinds.indices, id: \.self) { index in
                    let level = glow[index < 2 ? 0 : 1] * PlayerTokens.tubeVariance[index]
                    GlassTube(picture: kinds[index], glow: min(1, level))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.bottom, PlayerTokens.tubeFloorHeight / 2)
            // The front glass of the window.
            shape.fill(LinearGradient(stops: [.init(color: PlayerTokens.glassReflection, location: 0),
                                              .init(color: .clear, location: 0.35)],
                                      startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.black, lineWidth: 1) }
        .frame(width: PlayerTokens.displayWidth, height: PlayerTokens.tubeWindowHeight)
        .padding(Space.xs)
        .background { DisplayBezel() }
        .accessibilityElement()
        .accessibilityLabel("Válvulas")
        .accessibilityValue(glow.max() ?? 0 > TubeGlow.idle + 0.05 ? "brillan con la música" : "encendidas")
    }
}

/// The two tube pictures (Resources/Tubes, made by tools/tube_layers.py
/// from photo-real AI pictures): each one as the cold tube on black and,
/// apart, the amber light of its filament on black. Black adds nothing, so
/// both are laid on the window by light: the tube floats in the chamber and
/// its light can be turned up and down.
private enum TubePicture {
    case small, large

    var height: CGFloat {
        self == .small ? PlayerTokens.tubeSmallHeight : PlayerTokens.tubeLargeHeight
    }

    var cold: NSImage? { Self.load(self == .small ? "tube-small-cold" : "tube-large-cold") }
    var light: NSImage? { Self.load(self == .small ? "tube-small-glow" : "tube-large-glow") }

    private static var cache: [String: NSImage] = [:]

    private static func load(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// One tube: the cold glass, then its filament light on top, as bright as
/// `glow` (0 cold ... 1 brightest), with a soft bloom around it and light
/// pooling on the floor.
private struct GlassTube: View {
    let picture: TubePicture
    let glow: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            if picture == .large {
                // Its black bakelite base vanished with the photo's background: drawn back.
                UnevenRoundedRectangle(bottomLeadingRadius: Space.xs, bottomTrailingRadius: Space.xs, style: .continuous)
                    .fill(LinearGradient(colors: [PlayerTokens.tubeSocketBottom, PlayerTokens.tubeSocketTop,
                                                  PlayerTokens.tubeSocketBottom],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .top) { Rectangle().fill(PlayerTokens.panelHighlight).frame(height: 1) }
                    .frame(width: picture.height * PlayerTokens.tubeBaseWidth,
                           height: picture.height * PlayerTokens.tubeBaseHeight)
            }
            if let cold = picture.cold {
                Image(nsImage: cold).resizable().interpolation(.high).scaledToFit()
                    .blendMode(.screen)
            }
            if let light = picture.light {
                // The bloom: the light spread a little, as the eye sees a hot filament.
                Image(nsImage: light).resizable().scaledToFit()
                    .blur(radius: PlayerTokens.tubeBloom)
                    .opacity(PlayerTokens.tubeBloomStrength * glow)
                    .blendMode(.plusLighter)
                Image(nsImage: light).resizable().interpolation(.high).scaledToFit()
                    .opacity(min(1, PlayerTokens.tubeLightGain * glow))
                    .blendMode(.plusLighter)
            }
        }
        .frame(height: picture.height)
        .background(alignment: .bottom) {
            // Light pooling on the floor around the base.
            Ellipse()
                .fill(PlayerTokens.tubeFloorGlow.opacity(0.4 * glow))
                .frame(width: picture.height * 0.5, height: Space.md)
                .blur(radius: Space.sm)
        }
        .accessibilityHidden(true)
    }
}

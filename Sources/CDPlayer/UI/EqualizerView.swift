import CDPlayerKit
import SwiftUI

/// The graphic equalizer, built as a second hi-fi unit that matches the CD
/// player: the same brushed front, display glass, metal buttons, knob and
/// feet, the same width so it stacks under the player. Its own window,
/// with no title bar; drag the front to move it.
struct EqualizerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var naming = false
    @State private var newName = ""
    @State private var deleting: EQPreset?
    @State private var dragging = false

    private var eq: EqualizerModel { model.equalizer }

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
            eq.startWatching()
            // Once the window has its size: on top of the player.
            DispatchQueue.main.async { UnitStack.arrange() }
        }
        .onDisappear {
            eq.stopWatching()
            UnitStack.unitClosed()
        }
        .alert("Guardar ajuste", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Guardar") { eq.save(as: newName) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Guarda las diez bandas y el nivel con un nombre. Si ya existe, lo sustituye.")
        }
        .confirmationDialog("¿Borrar el ajuste \(deleting?.name ?? "")?", isPresented: deletingBinding,
                            presenting: deleting) { preset in
            Button("Borrar", role: .destructive) { eq.delete(preset) }
        } message: { _ in
            Text("No se puede deshacer. El sonido no cambia hasta que elijas otro ajuste.")
        }
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    // MARK: - Panel

    private var panel: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            leftColumn
            centerColumn
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
                RoundButton(help: "Cerrar el ecualizador (sigue sonando como está)") {
                    dismissWindow(id: EqualizerView.windowID)
                }
            }
        }
        .frame(width: 128, alignment: .leading)
    }

    /// The display, and the ten faders under it.
    private var centerColumn: some View {
        VStack(spacing: Space.md) {
            EQDisplay(eq: eq)
            HStack(spacing: 0) {
                ForEach(Array(Equalizer.bands.enumerated()), id: \.offset) { index, band in
                    VStack(spacing: Space.sm) {
                        EQFader(gain: eq.settings.gains[index], label: band.label,
                                help: "\(band.label) Hz: arrastra arriba o abajo; doble clic a 0",
                                set: { eq.setGain($0, band: index) },
                                nudge: { eq.nudgeGain(band: index, by: $0) })
                        ShelfSwitch(on: eq.isShelf(band: index),
                                    present: index == Equalizer.lowShelfBand || index == Equalizer.highShelfBand,
                                    help: index == Equalizer.lowShelfBand
                                        ? "Graves en estantería: sube o baja todo lo que hay por debajo, como el control de graves de un amplificador"
                                        : "Agudos en estantería: sube o baja todo lo que hay por encima, como el control de agudos de un amplificador") {
                            eq.toggleShelf(band: index)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: PlayerTokens.displayWidth)
        }
    }

    /// On/off and the saved settings; the level knob; the model name.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: Space.md) {
            HStack(alignment: .bottom, spacing: 0) {
                LabeledButton(label: "EQ", active: eq.settings.enabled,
                              help: "Encender o apagar el ecualizador, para comparar (E)") { eq.toggle() }
                    .frame(maxWidth: .infinity)
                StepButton(symbol: "chevron.left", help: "Ajuste guardado anterior") { eq.stepPreset(by: -1) }
                    .frame(maxWidth: .infinity)
                StepButton(symbol: "chevron.right", help: "Ajuste guardado siguiente") { eq.stepPreset(by: 1) }
                    .frame(maxWidth: .infinity)
                LabeledButton(label: "GUARDAR", help: "Guardar este ajuste con un nombre") {
                    newName = eq.presetName == EQPreset.neutralName ? "" : (eq.presetName ?? "")
                    naming = true
                }
                .frame(maxWidth: .infinity)
                LabeledButton(label: "BORRAR", help: "Borrar el ajuste guardado que suena ahora") {
                    deleting = eq.deletablePreset
                }
                .frame(maxWidth: .infinity)
            }
            HStack(alignment: .bottom, spacing: Space.xl) {
                LabeledButton(label: "NEUTRO", help: "Todas las bandas a 0 y el nivel al máximo: el sonido del CD tal cual") {
                    eq.flatten()
                }
                VStack(spacing: 0) {
                    RotaryKnob(value: 1 - eq.settings.preamp / Equalizer.minPreamp,
                               help: "Nivel general: bájalo si subes varias bandas y se enciende OVER",
                               accessibilityName: "Nivel",
                               accessibilityText: "\(Equalizer.label(eq.settings.preamp)) decibelios",
                               set: { eq.setPreamp((1 - $0) * Equalizer.minPreamp) },
                               nudge: { eq.nudgePreamp(by: $0) },
                               reset: { eq.setPreamp(0) })
                    EngravedLabel(text: "NIVEL")
                }
            }
            Spacer(minLength: 0)
            Text("GRAPHIC EQUALIZER  EQ-10")
                .font(PlayerTokens.modelFont)
                .tracking(1)
                .foregroundStyle(PlayerTokens.engravedDim)
        }
        .frame(width: 288)
    }

    static let windowID = "equalizer"
}

/// A small button with an arrow printed above it, the height of the mode
/// buttons beside it.
private struct StepButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Space.sm) {
            PrintedSymbols(symbols: [symbol])
            RoundButton(help: help, size: PlayerTokens.buttonSmall, action: action)
        }
    }
}

// MARK: - Display

/// The unit's fluorescent display: the setting's name, the curve the ten
/// bands make, and a peak meter per channel with its OVER light.
private struct EQDisplay: View {
    let eq: EqualizerModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .bottom, spacing: Space.sm) {
                DotLine(text: eq.flash ?? eq.presetName ?? "PERSONAL", cells: 22,
                        pitch: PlayerTokens.dotPitchTitle)
                Spacer(minLength: 0)
                DotLine(text: eq.settings.enabled ? "EQ ON" : "EQ OFF", cells: 6,
                        color: eq.settings.enabled ? PlayerTokens.displayText : PlayerTokens.displayTextDim,
                        trailing: true)
            }
            EQCurve(settings: eq.settings)
                .frame(height: PlayerTokens.eqCurveHeight)
            VStack(alignment: .leading, spacing: Space.xs) {
                PeakRow(channel: "L", level: eq.meters[0], overs: eq.overs[0], lit: eq.overUntil[0])
                PeakRow(channel: "R", level: eq.meters[1], overs: eq.overs[1], lit: eq.overUntil[1])
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DisplayGlass() }
        .padding(Space.xs)
        .background { DisplayBezel() }
        .frame(width: PlayerTokens.displayWidth)
    }
}

/// The equalizer's curve drawn in dots, 20 Hz to 20 kHz, ±12 dB, with the
/// 0 dB line and a mark under each band.
private struct EQCurve: View {
    let settings: EQSettings

    var body: some View {
        Canvas { context, size in
            let pitch = PlayerTokens.dotPitch
            let columns = Int(size.width / pitch)
            var rows = Int(size.height / pitch)
            if rows % 2 == 0 { rows -= 1 }
            let middle = rows / 2
            let top = (size.height - CGFloat(rows) * pitch) / 2
            let dot = pitch * PlayerTokens.dotFill
            let inset = (pitch - dot) / 2
            func cell(_ column: Int, _ row: Int) -> CGRect {
                CGRect(x: CGFloat(column) * pitch + inset, y: top + CGFloat(row) * pitch + inset,
                       width: dot, height: dot)
            }
            func frequency(_ column: Int) -> Double {
                20 * pow(1000, Double(column) / Double(max(1, columns - 1)))
            }
            var lit = Path()
            var zero = Path()
            var unlit = Path()
            var marks = Path()
            let bandColumns = Equalizer.bands.map { band in
                Int((log10(band.frequency / 20) / 3 * Double(columns - 1)).rounded())
            }
            var previousRow: Int?
            for column in 0..<columns {
                let gain = Equalizer.response(settings, at: frequency(column))
                let row = middle - Int((gain / Equalizer.maxGain * Double(middle)).rounded())
                let clamped = min(rows - 1, max(0, row))
                // Join steep parts so the line has no gaps.
                let span = previousRow.map { min($0, clamped)...max($0, clamped) } ?? clamped...clamped
                for line in 0..<rows {
                    let rect = cell(column, line)
                    if span.contains(line) {
                        lit.addEllipse(in: rect)
                    } else if line == middle {
                        zero.addEllipse(in: rect)
                    } else if line == rows - 1 && bandColumns.contains(column) {
                        marks.addEllipse(in: rect)
                    } else {
                        unlit.addEllipse(in: rect)
                    }
                }
                previousRow = clamped
            }
            let color = settings.enabled ? PlayerTokens.displayText : PlayerTokens.displayTextDim
            context.fill(unlit, with: .color(color.opacity(PlayerTokens.dotUnlitOpacity)))
            context.fill(zero, with: .color(PlayerTokens.eqZeroLine))
            context.fill(marks, with: .color(PlayerTokens.displayTextDim))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pitch * 1.4))
                glow.fill(lit, with: .color(color.opacity(PlayerTokens.dotGlowOpacity)))
            }
            context.fill(lit, with: .color(color))
        }
        .accessibilityElement()
        .accessibilityLabel("Curva del ecualizador")
    }
}

/// One channel's peak meter: a bar of dots up to full scale (the last
/// 3 dB in red), the OVER light, and how many times it went over.
private struct PeakRow: View {
    let channel: String
    let level: Double
    let overs: Int
    let lit: Date

    var body: some View {
        HStack(spacing: Space.sm) {
            DotLine(text: channel, cells: 1, pitch: PlayerTokens.dotPitchSmall)
            PeakBar(level: level)
                .frame(height: PlayerTokens.eqMeterHeight)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let on = context.date < lit
                DotLine(text: "OVER", cells: 4, pitch: PlayerTokens.dotPitchSmall,
                        color: on ? PlayerTokens.eqOver : PlayerTokens.eqOver.opacity(0.2))
            }
            DotLine(text: overs > 999 ? "999" : String(overs), cells: 3, pitch: PlayerTokens.dotPitchSmall,
                    color: overs > 0 ? PlayerTokens.eqOver : PlayerTokens.displayTextDim, trailing: true)
        }
        .accessibilityElement()
        .accessibilityLabel("Canal \(channel == "L" ? "izquierdo" : "derecho")")
        .accessibilityValue(overs > 0 ? "recortó \(overs) veces" : "sin recortes")
    }
}

private struct PeakBar: View {
    let level: Double

    var body: some View {
        Canvas { context, size in
            let pitch = PlayerTokens.dotPitch
            let columns = Int(size.width / pitch)
            let rows = Int(size.height / pitch)
            let dot = pitch * PlayerTokens.dotFill
            let inset = (pitch - dot) / 2
            let litColumns = Int((level * Double(columns)).rounded())
            // Where -3 dBFS falls: the red part of the scale.
            let red = Int(((-3 - PeakMeter.floor) / -PeakMeter.floor * Double(columns)).rounded())
            var lit = Path(), hot = Path(), unlit = Path(), redUnlit = Path()
            for column in 0..<columns {
                for row in 0..<rows {
                    let rect = CGRect(x: CGFloat(column) * pitch + inset, y: CGFloat(row) * pitch + inset,
                                      width: dot, height: dot)
                    switch (column < litColumns, column >= red) {
                    case (true, false): lit.addEllipse(in: rect)
                    case (true, true): hot.addEllipse(in: rect)
                    case (false, true): redUnlit.addEllipse(in: rect)
                    case (false, false): unlit.addEllipse(in: rect)
                    }
                }
            }
            context.fill(unlit, with: .color(PlayerTokens.displayText.opacity(PlayerTokens.dotUnlitOpacity * 3)))
            context.fill(redUnlit, with: .color(PlayerTokens.eqOver.opacity(0.15)))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pitch * 1.4))
                glow.fill(lit, with: .color(PlayerTokens.displayText.opacity(PlayerTokens.dotGlowOpacity)))
                glow.fill(hot, with: .color(PlayerTokens.eqOver.opacity(PlayerTokens.dotGlowOpacity)))
            }
            context.fill(lit, with: .color(PlayerTokens.displayText))
            context.fill(hot, with: .color(PlayerTokens.eqOver))
        }
    }
}

/// The small switch under the end faders: its light on, the band is a
/// shelf; off, a bell like the others. The other faders keep the room
/// empty, so every fader lines up.
private struct ShelfSwitch: View {
    let on: Bool
    let present: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                ModeLight(on: on)
                EngravedLabel(text: "SHELF")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(on ? "activado" : "desactivado")
        .opacity(present ? 1 : 0)
        .disabled(!present)
        .accessibilityHidden(!present)
    }
}

// MARK: - Fader

/// A slide fader in a slot cut into the front: a metal cap with a white
/// line, printed ticks every 6 dB, the frequency under it. Drag up or
/// down, arrow keys when it has focus, double-click to put it back at 0.
private struct EQFader: View {
    let gain: Double
    let label: String
    let help: String
    let set: (Double) -> Void
    let nudge: (Int) -> Void

    @State private var dragStart: Double?
    @FocusState private var focused: Bool

    private var capTop: CGFloat {
        CGFloat(1 - (gain + Equalizer.maxGain) / (2 * Equalizer.maxGain)) * PlayerTokens.faderDragRange
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            ZStack(alignment: .top) {
                FaderScale()
                Capsule()
                    .fill(LinearGradient(colors: [PlayerTokens.collarTop, PlayerTokens.collarBottom],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: PlayerTokens.faderSlotWidth)
                    .padding(.vertical, Space.xs)
                FaderCap()
                    .padding(.top, capTop)
            }
            .frame(width: PlayerTokens.faderCapWidth + 4 * Space.xs, height: PlayerTokens.faderHeight)
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.upArrow) { nudge(1); return .handled }
            .onKeyPress(.downArrow) { nudge(-1); return .handled }
            .onTapGesture(count: 2) { set(0) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        focused = true
                        if dragStart == nil { dragStart = gain }
                        let delta = -Double(drag.translation.height / PlayerTokens.faderDragRange) * 2 * Equalizer.maxGain
                        set((dragStart ?? gain) + delta)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .help(help)
            .accessibilityElement()
            .accessibilityLabel("\(label) hercios")
            .accessibilityValue("\(Equalizer.label(gain)) decibelios")
            .accessibilityAdjustableAction { direction in nudge(direction == .increment ? 1 : -1) }
            EngravedLabel(text: label)
        }
    }
}

private struct FaderCap: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [PlayerTokens.buttonFaceLight, PlayerTokens.buttonFaceDark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { Rectangle().fill(PlayerTokens.faderCapLine).frame(height: 1) }
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(PlayerTokens.buttonRimLight, lineWidth: 1)
            }
            .frame(width: PlayerTokens.faderCapWidth, height: PlayerTokens.faderCapHeight)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// Ticks printed beside the slot: every 6 dB, longer at 0.
private struct FaderScale: View {
    var body: some View {
        Canvas { context, size in
            let travel = PlayerTokens.faderDragRange
            let top = PlayerTokens.faderCapHeight / 2
            let centre = size.width / 2
            let gap = PlayerTokens.faderSlotWidth / 2 + PlayerTokens.faderTickShort
            for step in 0...4 {
                let y = top + travel * CGFloat(step) / 4
                let length = step == 2 ? PlayerTokens.faderTickLong + Space.xs : PlayerTokens.faderTickLong
                var path = Path()
                path.move(to: CGPoint(x: centre - gap - length, y: y))
                path.addLine(to: CGPoint(x: centre - gap, y: y))
                path.move(to: CGPoint(x: centre + gap, y: y))
                path.addLine(to: CGPoint(x: centre + gap + length, y: y))
                context.stroke(path, with: .color(PlayerTokens.knobTick), lineWidth: PlayerTokens.faderTickWidth)
            }
        }
        .accessibilityHidden(true)
    }
}

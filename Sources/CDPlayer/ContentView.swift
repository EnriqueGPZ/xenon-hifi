import AppKit
import SwiftUI

/// The whole window is the front of a hi-fi CD player standing on its feet:
/// no title bar, no toolbar. docs/BRIEF.md, "Look", is why the chrome is
/// custom instead of native. Drag the panel to move the window.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        VStack(spacing: 0) {
            panel
            feet
        }
        .padding(Space.lg)
        .noInitialFocus()
        .onChange(of: alwaysOnTop, initial: true) { _, onTop in
            WindowLevel.apply(floating: onTop)
        }
        .task {
            // Switched on, the whole stack comes up; units are closed one by
            // one if wanted. Tests and snapshots open their own.
            if !Store.isOverridden {
                for unit in UnitStack.order { openWindow(id: unit) }
            }
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
    }

    // MARK: - Panel

    private var panel: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            leftColumn
            centerColumn
            rightColumn
        }
        // As tall as the display column; the side columns stretch to match,
        // so POWER and the model name sit on the bottom edge.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.section + Space.xs)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
        .background { BrushedPanel() }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    /// The brand at the top; the power button with its pilot light at the bottom.
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLogo()
            Spacer(minLength: Space.lg)
            VStack(spacing: Space.xs) {
                PowerLED()
                PrintedSymbols(symbols: ["power"])
                RoundButton(help: "Apagar (cierra CDPlayer)") { NSApp.terminate(nil) }
            }
        }
        .frame(width: 128, alignment: .leading)
    }

    /// The tray door above the display, and the mode buttons under it.
    private var centerColumn: some View {
        VStack(spacing: Space.sm) {
            TrayDoor()
            MatrixDisplay(model: model)
            HStack(alignment: .top, spacing: 0) {
                LabeledButton(label: "FAVORITA", active: isFavorite,
                              help: "Marcar esta canción como favorita (F)") { model.toggleFavoriteCurrent() }
                    .frame(maxWidth: .infinity)
                LabeledButton(label: "SOLO FAV", active: model.favoritesOnly,
                              help: "Reproducir solo las favoritas (Mayúsculas F)") { model.toggleFavoritesOnly() }
                    .frame(maxWidth: .infinity)
                LabeledButton(label: "ALEATORIO", active: model.isShuffle,
                              help: "Orden aleatorio (S)") { model.toggleShuffle() }
                    .frame(maxWidth: .infinity)
                LabeledButton(label: "REPETIR", active: model.isRepeat,
                              help: "Repetir el disco (R)") { model.toggleRepeat() }
                    .frame(maxWidth: .infinity)
                LabeledButton(label: "DISPLAY", active: false,
                              help: "Cambiar la pantalla: transcurrido, restante, barras o vúmetros (D)") { model.cycleDisplay() }
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, Space.xs)
            .frame(width: PlayerTokens.displayWidth)
        }
    }

    /// The transport buttons, stop and eject, and the volume knob. Their
    /// symbols are printed on the front above them, as on a Denon.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: Space.md) {
            HStack(spacing: Space.md) {
                TransportButton(symbols: ["backward.end.fill"], help: "Canción anterior (⌘←)") { model.previous() }
                TransportButton(symbols: ["backward.fill"], help: "Retroceso rápido: mantén pulsado (⌥←)",
                                repeats: true) { model.rewind() }
                TransportButton(symbols: ["play.fill", "pause.fill"],
                                help: "Reproducir / pausa (espacio)") { model.playPause() }
                TransportButton(symbols: ["forward.fill"], help: "Avance rápido: mantén pulsado (⌥→)",
                                repeats: true) { model.fastForward() }
                TransportButton(symbols: ["forward.end.fill"], help: "Canción siguiente (⌘→)") { model.next() }
            }
            HStack(alignment: .top, spacing: Space.md) {
                TransportButton(symbols: ["stop.fill"], help: "Detener (⌘.)") { model.stop() }
                TransportButton(symbols: ["eject.fill"], help: "Expulsar el disco, o abrir la bandeja (⌘E)") { model.eject() }
                Spacer(minLength: Space.sm)
                // Both knob names on one line, as printed on the front.
                HStack(alignment: .bottom, spacing: Space.md) {
                    VStack(spacing: 0) {
                        BalanceKnob(model: model)
                        EngravedLabel(text: "BALANCE")
                    }
                    VStack(spacing: 0) {
                        VolumeKnob(model: model)
                        EngravedLabel(text: "VOLUMEN")
                    }
                }
            }
            Spacer(minLength: 0)
            Text("COMPACT DISC PLAYER  CDP-1")
                .font(PlayerTokens.modelFont)
                .tracking(1)
                .foregroundStyle(PlayerTokens.engravedDim)
        }
        .frame(width: 288)
    }

    private var isFavorite: Bool { model.currentTrack?.isFavorite == true }
    private var favoriteSymbol: String { isFavorite ? "star.fill" : "star" }

    // MARK: - Feet

    private var feet: some View {
        HStack {
            Foot()
            Spacer()
            Foot()
        }
        .padding(.horizontal, Space.section + Space.xl)
    }
}

/// Dark brushed metal: a vertical gradient with fine horizontal grain and a
/// lit top edge.
struct BrushedPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlayerTokens.panelRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [PlayerTokens.panelTop, PlayerTokens.panelBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Canvas { context, size in
                    var y: CGFloat = 0
                    var seed: UInt64 = 0x9E37_79B9
                    while y < size.height {
                        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let alpha = Double(seed >> 59) / 31 * 0.08
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), // grid: ok hairline grain
                                     with: .color(PlayerTokens.brushLine.opacity(alpha)))
                        y += 1
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay {
                // The case's side cheeks, darker than the brushed front.
                HStack(spacing: 0) {
                    cheek(startPoint: .leading, endPoint: .trailing)
                    Spacer(minLength: 0)
                    cheek(startPoint: .trailing, endPoint: .leading)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PlayerTokens.panelHighlight)
                    .frame(height: 1)
                    .padding(.horizontal, PlayerTokens.cheekWidth)
            }
            .overlay(shape.strokeBorder(PlayerTokens.panelEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }

    private func cheek(startPoint: UnitPoint, endPoint: UnitPoint) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [PlayerTokens.cheekDark, PlayerTokens.cheekLight],
                                 startPoint: startPoint, endPoint: endPoint))
            .frame(width: PlayerTokens.cheekWidth)
            .overlay(alignment: startPoint == .leading ? .trailing : .leading) {
                Rectangle().fill(.black.opacity(0.7)).frame(width: 1)
            }
    }
}

/// The disc tray door above the display: a metal flap with a shadow gap
/// above it and a lit lower lip, as on the reference player.
private struct TrayDoor: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [PlayerTokens.doorTop, PlayerTokens.doorBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(.black).frame(height: 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(PlayerTokens.panelHighlight).frame(height: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(.black.opacity(0.9), lineWidth: 1)
            }
            .frame(width: PlayerTokens.displayWidth, height: PlayerTokens.doorHeight)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// A round machined foot, seen from the front: a cylinder lit in the
/// middle, with a dark gap under the case and a ring line.
struct Foot: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(stops: [.init(color: PlayerTokens.footBottom, location: 0),
                                         .init(color: PlayerTokens.footTop, location: 0.35),
                                         .init(color: PlayerTokens.footBottom, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) {
                Rectangle().fill(.black.opacity(0.8)).frame(height: 2)
            }
            .overlay {
                Rectangle().fill(PlayerTokens.panelHighlight).frame(height: 1)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous))
            .frame(width: PlayerTokens.footWidth, height: PlayerTokens.footHeight)
            .accessibilityHidden(true)
    }
}

/// "Siempre en primer plano" (Settings and the Window menu): lifts the
/// player's window above every other app's windows.
enum WindowLevel {
    static func apply(floating: Bool) {
        // The window may not exist yet on the first call; try again shortly.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true {
                window.level = floating ? .floating : .normal
                // The equalizer unit stacked on top keeps the same level.
                for child in window.childWindows ?? [] { child.level = window.level }
                window.collectionBehavior.insert(.fullScreenAuxiliary)
            }
        }
    }
}

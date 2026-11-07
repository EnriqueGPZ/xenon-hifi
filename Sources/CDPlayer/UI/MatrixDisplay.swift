import SwiftUI
import CDPlayerKit

/// The fluorescent dot-matrix display: play state, track number, a big
/// clock, the title scrolling one character at a time, artist and album,
/// and the mode words that light up like the printed segments of a real
/// player's display. Every character is drawn as 5×7 dots (DotMatrix.swift).
struct MatrixDisplay: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .bottom, spacing: Space.sm) {
                DotLine(text: trackText, cells: 13)
                Spacer(minLength: 0)
                DotLine(text: timeCaption, cells: 5, pitch: PlayerTokens.dotPitchSmall)
                DotLine(text: timeText, cells: 6, pitch: PlayerTokens.dotPitchLarge, trailing: true)
            }

            DotLine(text: titleText, cells: 27, pitch: PlayerTokens.dotPitchTitle, scrolls: true)

            DotLine(text: secondLine, cells: 34,
                    color: model.flash == nil ? PlayerTokens.displayTextDim : PlayerTokens.displayText,
                    scrolls: model.flash == nil)

            HStack(spacing: Space.sm) {
                annunciator("ALEATORIO", on: model.isShuffle)
                annunciator("REPETIR", on: model.isRepeat)
                annunciator("SOLO FAV", on: model.favoritesOnly)
                annunciator("★", on: model.currentTrack?.isFavorite == true)
                Spacer(minLength: 0)
                DotLine(text: discText, cells: 15, pitch: PlayerTokens.dotPitchSmall,
                        color: PlayerTokens.displayTextDim, trailing: true)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The bars and the meters take the whole display; the text keeps its size.
        .opacity(model.displayMode.showsSound ? 0 : 1)
        .overlay {
            switch model.displayMode {
            case .spectrum:
                SpectrumView(meter: model.spectrum)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
            case .vu:
                VUMetersView(meters: model.vuMeters)
                    .padding(Space.xs)
            case .elapsed, .remaining:
                EmptyView()
            }
        }
        .background { DisplayGlass() }
        .padding(Space.xs)
        .background { DisplayBezel() }
        .frame(width: PlayerTokens.displayWidth)
        .accessibilityElement(children: .combine)
    }

    private var trackText: String {
        let state = switch model.playbackState {
        case .playing: "▶"
        case .paused: "‖"
        case .stopped: "■"
        }
        guard let track = model.currentTrack else { return "\(state) PISTA --" }
        return String(format: "%@ PISTA %02d/%02d", state, track.number, model.tracks.count)
    }

    private var timeCaption: String {
        guard model.disc != nil else { return "" }
        return switch model.displayMode {
        case .elapsed, .spectrum, .vu: ""
        case .remaining: "RESTA"
        }
    }

    private var timeText: String {
        guard let track = model.currentTrack else { return "--:--" }
        return switch model.displayMode {
        case .elapsed, .spectrum, .vu: TrackTime.format(model.elapsed)
        case .remaining: "-" + TrackTime.format(track.duration - model.elapsed)
        }
    }

    private var titleText: String {
        model.currentTrack?.title ?? "SIN DISCO"
    }

    private var secondLine: String {
        if let flash = model.flash { return flash }
        guard let disc = model.disc else { return "Introduce un CD" }
        if model.isLookingUp { return "Buscando títulos…" }
        let artist = model.currentArtist
        let album = disc.year.isEmpty ? disc.title : "\(disc.title) (\(disc.year))"
        return artist.isEmpty ? album : "\(artist) – \(album)"
    }

    private var discText: String {
        guard model.disc != nil else { return "" }
        return "\(model.tracks.count) PISTAS \(TrackTime.format(model.totalDuration))"
    }

    /// A mode word: bright when on, a faint printed ghost when off, as on a
    /// real fluorescent display.
    private func annunciator(_ text: String, on: Bool) -> some View {
        DotLine(text: text, cells: text.count, pitch: PlayerTokens.dotPitchSmall,
                color: on ? PlayerTokens.displayText : PlayerTokens.displayGhost)
    }
}

/// The spectrum bars across the whole display: one column of dots per
/// band, lows on the left, a peak dot above each bar, and a red base line,
/// like the bar graph on a hi-fi fluorescent display.
private struct SpectrumView: View {
    let meter: SpectrumMeter

    var body: some View {
        Canvas { context, size in
            let bands = SpectrumMeter.bandCount
            let barDots = PlayerTokens.spectrumBarDots
            let columns = bands * (barDots + 1) - 1
            let pitch = size.width / CGFloat(columns)
            let rows = Int(size.height / pitch)
            let barRows = rows - 2
            let top = size.height - CGFloat(rows) * pitch
            let dot = pitch * PlayerTokens.dotFill
            let inset = (pitch - dot) / 2
            func cell(_ column: Int, _ row: Int) -> CGRect {
                CGRect(x: CGFloat(column) * pitch + inset, y: top + CGFloat(row) * pitch + inset,
                       width: dot, height: dot)
            }
            var lit = Path()
            var unlit = Path()
            var base = Path()
            for band in 0..<bands {
                let height = Int((CGFloat(meter.levels[band]) * CGFloat(barRows)).rounded())
                let peak = Int((CGFloat(meter.peaks[band]) * CGFloat(barRows)).rounded())
                for dotColumn in 0..<barDots {
                    let column = band * (barDots + 1) + dotColumn
                    base.addEllipse(in: cell(column, rows - 1))
                    for level in 0..<barRows {
                        let rect = cell(column, rows - 3 - level)
                        if level < height || (peak > 0 && level == peak - 1) {
                            lit.addEllipse(in: rect)
                        } else {
                            unlit.addEllipse(in: rect)
                        }
                    }
                }
            }
            let color = PlayerTokens.displayText
            context.fill(unlit, with: .color(color.opacity(PlayerTokens.dotUnlitOpacity)))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pitch * 1.4))
                glow.fill(lit, with: .color(color.opacity(PlayerTokens.dotGlowOpacity)))
                glow.fill(base, with: .color(PlayerTokens.spectrumBase.opacity(PlayerTokens.dotGlowOpacity)))
            }
            context.fill(lit, with: .color(color))
            context.fill(base, with: .color(PlayerTokens.spectrumBase))
        }
        .accessibilityElement()
        .accessibilityLabel("Barras del sonido")
    }
}

/// The black glass of the display, with a faint reflection across its top.
struct DisplayGlass: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlayerTokens.displayRadius, style: .continuous)
        shape
            .fill(PlayerTokens.displayBackground)
            .overlay {
                shape.fill(LinearGradient(stops: [.init(color: PlayerTokens.glassReflection, location: 0),
                                                  .init(color: .clear, location: 0.45)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay { shape.strokeBorder(.black, lineWidth: 1) }
    }
}

/// The recessed frame the display window sits in: shaded at the top, lit
/// along the bottom edge, like a cut in the metal front.
struct DisplayBezel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlayerTokens.bezelRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [PlayerTokens.bezelTop, PlayerTokens.bezelBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.8), PlayerTokens.panelHighlight],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}

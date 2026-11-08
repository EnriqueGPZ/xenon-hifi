import AppKit
import CDPlayerKit
import SwiftUI

/// The file player: a third hi-fi unit that plays MP3 and FLAC from the
/// disks the listener plugs in. Same brushed front, buttons, knob and feet as
/// the CD player and the equalizer, and the same width so the three stack.
/// The one new thing is a colour screen, for the album cover.
struct FilePlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var dragging = false
    @State private var arrowKeys: Any?

    private var files: FilePlayerModel { model.filePlayer }

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
            DispatchQueue.main.async { UnitStack.arrange() }
            arrowKeys = installArrowKeys()
        }
        .onDisappear {
            UnitStack.unitClosed()
            if let arrowKeys { NSEvent.removeMonitor(arrowKeys) }
            arrowKeys = nil
        }
    }

    /// ↑ and ↓ move through the list like one click of SELECCIÓN, while this
    /// unit was the last one clicked. The units hang from the CD player's
    /// window and never become the key window, so the keys arrive at the
    /// player's: what counts is where the last click landed.
    private func installArrowKeys() -> Any? {
        var lastClickHere = false
        return NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [files] event in
            if event.type == .leftMouseDown {
                lastClickHere = event.window?.identifier?.rawValue.hasPrefix(FilePlayerView.windowID) == true
                return event
            }
            guard lastClickHere,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            switch event.keyCode {
            case Self.upKey: files.moveHighlight(by: -1)
            case Self.downKey: files.moveHighlight(by: 1)
            default: return event
            }
            return nil
        }
    }

    private static let upKey: UInt16 = 126
    private static let downKey: UInt16 = 125

    private var panel: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            leftColumn
            FileScreen(files: files)
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
                RoundButton(help: "Apagar el reproductor de archivos (la música se para)") {
                    files.stop()
                    dismissWindow(id: FilePlayerView.windowID)
                }
            }
        }
        .frame(width: 128, alignment: .leading)
    }

    /// Previous, play/pause, next and the music folder; the list and the
    /// big knob to browse; the model name.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: Space.md) {
            HStack(alignment: .bottom, spacing: 0) {
                scan("backward.end.fill",
                     help: "Canción anterior; mantén pulsado para retroceder (⇧⌥⌘←)",
                     tap: { files.previous() }, hold: { files.skip(by: -FilePlayerModel.scanStep) })
                transport("playpause.fill", help: "Reproducir o pausar (⌥ espacio)") { files.playPause() }
                scan("forward.end.fill",
                     help: "Canción siguiente; mantén pulsado para avanzar (⇧⌥⌘→)",
                     tap: { files.next() }, hold: { files.skip(by: FilePlayerModel.scanStep) })
                LabeledButton(label: "MÚSICA", help: "Elegir el disco o la carpeta con la música (⌥⌘O)") {
                    files.chooseFolder()
                }
                .frame(maxWidth: .infinity)
            }
            HStack(alignment: .bottom, spacing: Space.xl) {
                LabeledButton(label: "FAVORITA", active: files.isFavorite(files.current),
                              help: "Marcar la canción que suena como favorita; están en ★ Favoritas (⌥⌘F)") {
                    files.toggleFavorite()
                }
                LabeledButton(label: "LISTA", active: files.screen != .nowPlaying,
                              help: "Cambia la pantalla: álbumes, canciones, carpetas y lo que suena (⌥⌘L)") {
                    files.toggleList()
                }
                VStack(spacing: 0) {
                    RotaryKnob(value: knobValue,
                               help: "Gira para moverte por la lista, de uno en uno; doble clic para elegir",
                               accessibilityName: "Selección",
                               accessibilityText: files.rows.indices.contains(files.highlight)
                                   ? files.rows[files.highlight] : "",
                               set: { _ in },
                               nudge: { files.moveHighlight(by: -$0) },
                               reset: { files.choose() },
                               step: { files.moveHighlight(by: $0) })
                    EngravedLabel(text: "SELECCIÓN")
                }
            }
            Spacer(minLength: 0)
            Text("MUSIC FILE PLAYER  MF-1")
                .font(PlayerTokens.modelFont)
                .tracking(1)
                .foregroundStyle(PlayerTokens.engravedDim)
        }
        .frame(width: 288)
    }

    /// An endless knob: its mark turns a notch for every row, round and round.
    private var knobValue: Double {
        let notches = 12
        return Double(files.highlight % notches) / Double(notches - 1)
    }

    private func transport(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: Space.sm) {
            PrintedSymbols(symbols: [symbol])
            RoundButton(help: help, size: PlayerTokens.buttonSmall, action: action)
        }
        .frame(maxWidth: .infinity)
    }

    private func scan(_ symbol: String, help: String, tap: @escaping () -> Void,
                      hold: @escaping () -> Void) -> some View {
        VStack(spacing: Space.sm) {
            PrintedSymbols(symbols: [symbol])
            HoldButton(help: help, tap: tap, hold: hold)
        }
        .frame(maxWidth: .infinity)
    }

    static let windowID = "fileplayer"
}

// MARK: - Screen

/// The colour screen behind the bezel: the song with its cover, or the
/// lists of albums and songs to choose from.
private struct FileScreen: View {
    let files: FilePlayerModel

    var body: some View {
        Group {
            if files.folder == nil {
                message("Pulsa MÚSICA y elige el disco o la carpeta donde está tu música.")
            } else if files.albums.isEmpty, let scanning = files.scanning {
                message("Leyendo la música… \(scanning.done) de \(scanning.total)")
            } else if files.albums.isEmpty {
                message(files.folderMissing ? "El disco de la música no está conectado."
                                            : "No hay canciones en esta carpeta.")
            } else if files.screen == .nowPlaying {
                NowPlayingScreen(files: files)
            } else {
                ListScreen(files: files)
            }
        }
        .padding(Space.md)
        .frame(width: PlayerTokens.displayWidth, height: PlayerTokens.screenHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: PlayerTokens.displayRadius)
                .fill(PlayerTokens.screenBackground)
        }
        .padding(Space.xs)
        .background { DisplayBezel() }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: Space.md) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 28, weight: .ultraLight))
            Text(text)
                .font(PlayerTokens.screenArtistFont)
                .multilineTextAlignment(.center)
            if let flash = files.flash { FooterLine(text: flash, accent: true) }
        }
        .foregroundStyle(PlayerTokens.screenTextDim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The line at the bottom of the screen: where the music comes from, or a
/// short message.
private struct FooterLine: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text.uppercased())
            .font(PlayerTokens.screenQualityFont)
            .tracking(0.6)
            .foregroundStyle(accent ? PlayerTokens.screenAccent : PlayerTokens.screenTextFaint)
            .lineLimit(1)
    }
}

private func sourceLine(_ files: FilePlayerModel) -> String {
    if let scanning = files.scanning { return "LEYENDO \(scanning.done) DE \(scanning.total)" }
    let name = files.folder?.lastPathComponent ?? ""
    return "\(name) · \(files.trackCount.formatted()) CANCIONES"
}

/// The song that plays: cover, names, the sound's quality in gold, progress.
private struct NowPlayingScreen: View {
    let files: FilePlayerModel

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            CoverView(image: files.cover)
            VStack(alignment: .leading, spacing: 0) {
                if let track = files.current {
                    Text(track.title)
                        .font(PlayerTokens.screenTitleFont)
                        .foregroundStyle(PlayerTokens.screenText)
                    Text(track.artist)
                        .font(PlayerTokens.screenArtistFont)
                        .foregroundStyle(PlayerTokens.screenTextDim)
                        .padding(.top, Space.xs)
                    Text([track.album, track.year].compactMap { $0 }.joined(separator: " · "))
                        .font(PlayerTokens.screenAlbumFont)
                        .foregroundStyle(PlayerTokens.screenTextFaint)
                        .padding(.top, 2)
                    HStack(spacing: Space.sm) {
                        Text(track.quality)
                            .tracking(0.6)
                        if files.isFavorite(track) {
                            Image(systemName: "star.fill").accessibilityLabel("Favorita")
                        }
                    }
                    .font(PlayerTokens.screenQualityFont)
                    .foregroundStyle(PlayerTokens.screenAccent)
                    .padding(.top, Space.md)
                    Spacer(minLength: Space.sm)
                    Progress(elapsed: files.elapsed, duration: track.duration) { files.seek(to: $0) }
                } else {
                    Text("\(files.albums.count.formatted()) álbumes")
                        .font(PlayerTokens.screenTitleFont)
                        .foregroundStyle(PlayerTokens.screenText)
                    Text("Gira SELECCIÓN o pulsa LISTA para elegir")
                        .font(PlayerTokens.screenArtistFont)
                        .foregroundStyle(PlayerTokens.screenTextDim)
                        .padding(.top, Space.xs)
                    Spacer(minLength: Space.sm)
                }
                FooterLine(text: files.flash ?? sourceLine(files), accent: files.flash != nil)
                    .padding(.top, Space.sm)
            }
            .lineLimit(1)
        }
    }
}

/// The albums, or one album's songs, with the highlighted row in gold.
/// A click opens or plays a row.
private struct ListScreen: View {
    let files: FilePlayerModel
    private let visible = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(PlayerTokens.screenQualityFont)
                    .tracking(0.6)
                    .foregroundStyle(PlayerTokens.screenTextFaint)
                Spacer()
                Text("\(files.highlight + 1) / \(files.rows.count)")
                    .font(PlayerTokens.screenTimeFont)
                    .foregroundStyle(PlayerTokens.screenTextFaint)
            }
            .lineLimit(1)
            .padding(.bottom, Space.xs)
            ForEach(window, id: \.self) { row in
                rowView(row)
            }
            Spacer(minLength: 0)
            FooterLine(text: files.flash ?? sourceLine(files), accent: files.flash != nil)
        }
    }

    private var title: String {
        if let album = files.albumForList { return "\(album.artist) · \(album.title)".uppercased() }
        return files.screen == .folders ? "CARPETAS" : "ÁLBUMES"
    }

    /// The rows around the highlight that fit on the screen.
    private var window: [Int] {
        let count = files.rows.count
        let first = min(max(0, files.highlight - visible / 2), max(0, count - visible))
        return Array(first..<min(count, first + visible))
    }

    private func rowView(_ row: Int) -> some View {
        let lit = row == files.highlight
        return HStack(spacing: Space.sm) {
            Text(primary(row))
                .font(PlayerTokens.screenAlbumFont)
                .foregroundStyle(lit ? PlayerTokens.screenAccent : PlayerTokens.screenText)
            Spacer(minLength: Space.sm)
            Text(secondary(row))
                .font(PlayerTokens.screenTimeFont)
                .foregroundStyle(PlayerTokens.screenTextFaint)
        }
        .lineLimit(1)
        .padding(.horizontal, Space.xs)
        .frame(height: PlayerTokens.listRowHeight)
        .background {
            if lit { RoundedRectangle(cornerRadius: PlayerTokens.coverRadius).fill(PlayerTokens.screenTrack) }
        }
        .contentShape(Rectangle())
        .onTapGesture { files.choose(row) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { files.choose(row) }
    }

    private func primary(_ row: Int) -> String {
        if let album = files.albumForList {
            let track = album.tracks[row]
            let number = album.isLooseSongs ? row + 1 : track.trackNumber
            return "\(number.map { "\($0)  " } ?? "")\(track.title)"
        }
        if files.screen == .folders { return files.folders[row].name }
        return files.listAlbums[row].title
    }

    private func secondary(_ row: Int) -> String {
        if let album = files.albumForList {
            let seconds = Int(album.tracks[row].duration)
            let star = !album.isFavorites && files.isFavorite(album.tracks[row]) ? "★  " : ""
            return star + String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        if files.screen == .folders {
            let count = files.folders[row].tracks.count
            return count == 1 ? "1 canción" : "\(count) canciones"
        }
        return files.listAlbums[row].artist
    }
}

private struct CoverView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                // No cover in the file or its folder: a quiet disc.
                ZStack {
                    PlayerTokens.screenTrack
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(PlayerTokens.screenTextFaint)
                }
            }
        }
        .frame(width: PlayerTokens.coverSize, height: PlayerTokens.coverSize)
        .clipShape(RoundedRectangle(cornerRadius: PlayerTokens.coverRadius))
    }
}

private struct Progress: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let seek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PlayerTokens.screenTrack)
                    Capsule().fill(PlayerTokens.screenTextDim)
                        .frame(width: proxy.size.width * min(1, elapsed / max(duration, 1)))
                }
                .frame(maxHeight: .infinity)
                // A taller strip than the line, so it is easy to hit.
                .contentShape(Rectangle().inset(by: -Space.sm))
                .onTapGesture { point in
                    seek(max(0, min(1, point.x / max(proxy.size.width, 1))) * duration)
                }
            }
            .frame(height: PlayerTokens.progressHeight)
            .help("Pulsa en la línea para ir a ese punto de la canción")
            HStack {
                Text(time(elapsed))
                Spacer()
                Text("-" + time(duration - elapsed))
            }
            .font(PlayerTokens.screenTimeFont)
            .foregroundStyle(PlayerTokens.screenTextDim)
        }
    }

    private func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

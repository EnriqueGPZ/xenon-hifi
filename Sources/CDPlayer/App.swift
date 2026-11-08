import AppKit
import CDPlayerKit
import SwiftData
import SwiftUI

// CDPlayer
//   CDPlayer                      the app
//   APP_STORE=<file> CDPlayer     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> CDPlayer   save a PNG of the player and every Settings tab in light and dark mode, then quit
//   APP_SEED=1 CDPlayer           fill an empty /tmp store with the demo disc (tools/snap.sh)
//   With APP_STORE set, the app never touches the real CD drive or the media keys.
//   CDPlayer --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> CDPlayer      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 CDPlayer           draw the 8 pt grid and the layout probes over the window

@main
struct CDPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some Scene {
        Window("CDPlayer", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .modelContainer(model.container)
        // The window is the device itself: no title bar, see-through around
        // the panel and its feet (ContentView).
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
            PlayerCommands(model: model)
            CommandGroup(after: .windowArrangement) {
                Toggle("Siempre en primer plano", isOn: $alwaysOnTop)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }

        // The graphic equalizer: a second unit that matches the player.
        Window("Ecualizador", id: EqualizerView.windowID) {
            EqualizerView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        // It moves with the player, never on its own (UI/UnitStack.swift).
        .windowBackgroundDragBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        // The tube preamp: a unit with four glowing tubes that warm the sound.
        Window("Previo a válvulas", id: TubeView.windowID) {
            TubeView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        // It moves with the player, never on its own (UI/UnitStack.swift).
        .windowBackgroundDragBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("Reproductor de archivos", id: FilePlayerView.windowID) {
            FilePlayerView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        // The guide: every unit, how it treats the sound, every control.
        Window("Ayuda de CDPlayer", id: HelpView.windowID) {
            HelpView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
        }
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

/// The "Reproducción" menu: every button on the panel, with its shortcut.
struct PlayerCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Reproducción") {
            Button(model.playbackState == .playing ? "Pausa" : "Reproducir") { model.playPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.disc == nil)
            Button("Detener") { model.stop() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(model.disc == nil)
            Button(model.disc == nil ? "Abrir bandeja" : "Expulsar") { model.eject() }
                .keyboardShortcut("e", modifiers: [.command])
            Divider()
            Button("Canción siguiente") { model.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(model.disc == nil)
            Button("Canción anterior") { model.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(model.disc == nil)
            Button("Avance rápido") { model.fastForward() }
                .keyboardShortcut(.rightArrow, modifiers: [.option])
                .disabled(model.disc == nil)
            Button("Retroceso rápido") { model.rewind() }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
                .disabled(model.disc == nil)
            Divider()
            Button("Subir volumen") { model.nudgeVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: [.command])
            Button("Bajar volumen") { model.nudgeVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
            Button("Balance a la izquierda") { model.nudgeBalance(by: -Balance.step) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            Button("Balance a la derecha") { model.nudgeBalance(by: Balance.step) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Centrar balance") { model.centerBalance() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Toggle("Favorita", isOn: Binding(get: { model.currentTrack?.isFavorite == true },
                                             set: { _ in model.toggleFavoriteCurrent() }))
                .keyboardShortcut("f", modifiers: [])
                .disabled(model.currentTrack == nil)
            Toggle("Solo favoritas", isOn: Binding(get: { model.favoritesOnly },
                                                   set: { _ in model.toggleFavoritesOnly() }))
                .keyboardShortcut("f", modifiers: [.shift])
                .disabled(model.disc == nil)
            Toggle("Aleatorio", isOn: Binding(get: { model.isShuffle }, set: { _ in model.toggleShuffle() }))
                .keyboardShortcut("s", modifiers: [])
            Toggle("Repetir", isOn: Binding(get: { model.isRepeat }, set: { _ in model.toggleRepeat() }))
                .keyboardShortcut("r", modifiers: [])
            Button("Cambiar pantalla") { model.cycleDisplay() }
                .keyboardShortcut("d", modifiers: [])
            Divider()
            Button("Ecualizador…") { openWindow(id: EqualizerView.windowID) }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Toggle("Ecualizador encendido", isOn: Binding(get: { model.equalizer.settings.enabled },
                                                          set: { _ in model.equalizer.toggle() }))
                .keyboardShortcut("e", modifiers: [])
            Button("Ecualizador neutro") { model.equalizer.flatten() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            Divider()
            Button("Previo a válvulas…") { openWindow(id: TubeView.windowID) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Toggle("Válvulas encendidas", isOn: Binding(get: { model.tube.settings.enabled },
                                                        set: { _ in model.tube.toggle() }))
                .keyboardShortcut("v", modifiers: [])
            Button("Más calidez") { model.tube.nudgeWarmth(by: 1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Menos calidez") { model.tube.nudgeWarmth(by: -1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Toggle("Crossfeed (auriculares)", isOn: Binding(get: { model.tube.crossfeed.enabled },
                                                            set: { _ in model.tube.toggleCrossfeed() }))
                .keyboardShortcut("c", modifiers: [])
            Picker("Nivel de crossfeed", selection: Binding(get: { model.tube.crossfeed.level },
                                                            set: { model.tube.setCrossfeedLevel($0) })) {
                ForEach(CrossfeedLevel.allCases, id: \.self) { level in
                    Text(level.label.capitalized).tag(level)
                }
            }
            Button("Siguiente nivel de crossfeed") { model.tube.nextCrossfeedLevel() }
                .keyboardShortcut("c", modifiers: [.shift])
        }
        // The music file player unit: its buttons, with ⌥ so they never
        // clash with the CD player's.
        CommandMenu("Archivos") {
            let files = model.filePlayer
            Button("Reproductor de archivos…") { openWindow(id: FilePlayerView.windowID) }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Elegir música…") { files.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Buscar canciones nuevas") { files.rescan() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(files.folder == nil)
            Divider()
            Button(files.isPlaying ? "Pausa" : "Reproducir") { files.playPause() }
                .keyboardShortcut(.space, modifiers: [.option])
            Button("Detener") { files.stop() }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(files.current == nil)
            Button("Canción siguiente") { files.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(files.current == nil)
            Button("Canción anterior") { files.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(files.current == nil)
            Button("Avanzar 5 segundos") { files.skip(by: FilePlayerModel.scanStep) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])
                .disabled(files.current == nil)
            Button("Retroceder 5 segundos") { files.skip(by: -FilePlayerModel.scanStep) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])
                .disabled(files.current == nil)
            Divider()
            Toggle("Favorita", isOn: Binding(get: { files.isFavorite(files.current) },
                                             set: { _ in files.toggleFavorite() }))
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(files.current == nil)
            Button("Cambiar vista (álbumes, canciones, carpetas)") { files.toggleList() }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
        // The help guide (Help/HelpContent.swift).
        CommandGroup(replacing: .help) {
            Button("Ayuda de CDPlayer") { openWindow(id: HelpView.windowID) }
                .keyboardShortcut("?", modifiers: [.command])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/CDPlayer/CDPlayer.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "CDPlayer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "CDPlayer.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Disc.self, Track.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}

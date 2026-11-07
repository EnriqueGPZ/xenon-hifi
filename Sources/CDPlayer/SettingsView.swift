import SwiftUI

/// The Settings window (Command-Comma): one grouped Form, sized to its content.
struct SettingsView: View {
    var body: some View {
        Form {
            GeneralSettings()
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 460)
        .noInitialFocus()
    }
}

/// The Settings pages. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }
}

struct GeneralSettings: View {
    @AppStorage("lookUpTitles") private var lookUpTitles = true
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        Section {
            Toggle("Buscar títulos en internet", isOn: $lookUpTitles)
        } header: {
            Text("Títulos")
        } footer: {
            Text("La primera vez que metes un disco, CDPlayer pregunta a MusicBrainz el álbum, el artista y las canciones, y los guarda para no volver a preguntar.")
        }
        Section("Al meter un CD") {
            Toggle("Empezar a sonar en cuanto se lea", isOn: $autoPlay)
        }
        Section {
            Toggle("Siempre en primer plano", isOn: $alwaysOnTop)
        } header: {
            Text("Ventana")
        } footer: {
            Text("El reproductor se queda por encima de las demás ventanas. También en el menú Ventana (⌥⌘T).")
        }
    }
}

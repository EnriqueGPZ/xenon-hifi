import Foundation
import SwiftData

/// A demo disc for snapshots and for trying the app before real CD-drive
/// reading exists (docs/BRIEF.md, "Not in version one"). APP_SEED=1 with
/// APP_STORE in /tmp fills an empty store with one sample CD.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Disc>())) ?? 0) == 0 else { return }
        let disc = Disc(discID: "demo-0001", title: "Álbum de ejemplo", artist: "Artista de ejemplo")
        context.insert(disc)
        let samples: [(String, TimeInterval, Bool)] = [
            ("Primera luz", 198, true),
            ("Carretera y manta", 231, false),
            ("Ciudad dormida", 264, false),
            ("Nada que perder", 183, true),
            ("Vuelta a empezar", 247, false),
            ("Tormenta de verano", 212, false),
            ("Despacio", 301, false),
            ("El último tren", 226, false),
        ]
        for (index, sample) in samples.enumerated() {
            let track = Track(number: index + 1, title: sample.0, duration: sample.1, disc: disc)
            track.isFavorite = sample.2
            context.insert(track)
        }
        try? context.save()
        model.loadLatestDisc()
    }
}

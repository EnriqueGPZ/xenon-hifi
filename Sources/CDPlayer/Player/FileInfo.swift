import AppKit
import AVFoundation
import CDPlayerKit

/// Reads what a music file is: its tags (title, artist, album…), its sound
/// (format, sample rate, bits) and its cover. Runs off the main thread: a
/// disk that was asleep can take a moment to answer.
nonisolated enum FileInfo {
    /// The song in `url`, or nil when the Mac cannot play the file.
    static func track(at url: URL) async -> LibraryTrack? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let description = file.fileFormat.streamDescription.pointee
        let rate = file.fileFormat.sampleRate
        let asset = AVURLAsset(url: url)
        var pairs: [(identifier: String, value: String)] = []
        for item in (try? await asset.load(.metadata)) ?? [] {
            guard let identifier = item.identifier?.rawValue,
                  let value = try? await item.load(.stringValue) else { continue }
            pairs.append((identifier, value))
        }
        let tags = SongTags(pairs)
        let lossy = [kAudioFormatMPEGLayer3, kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE].contains(description.mFormatID)
        var bitRate: Int?
        if lossy, let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let dataRate = try? await track.load(.estimatedDataRate), dataRate > 0 {
            bitRate = Int((dataRate / 1000).rounded())
        }
        let folder = url.deletingLastPathComponent()
        return LibraryTrack(
            path: url.path,
            title: tags.title ?? url.deletingPathExtension().lastPathComponent,
            artist: tags.artist ?? tags.albumArtist ?? "ARTISTA DESCONOCIDO",
            album: tags.album ?? folder.lastPathComponent,
            albumArtist: tags.albumArtist,
            trackNumber: tags.trackNumber, discNumber: tags.discNumber, year: tags.year,
            duration: Double(file.length) / rate,
            format: formatName(description.mFormatID, extension: url.pathExtension),
            sampleRate: rate,
            bits: lossy ? nil : bits(description),
            bitRate: bitRate,
            modified: values?.contentModificationDate ?? .distantPast)
    }

    /// The picture inside the file, or else one beside it in its folder
    /// (cover.jpg, folder.jpg, front.png…).
    static func cover(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        for item in (try? await asset.load(.metadata)) ?? [] {
            let key = item.identifier?.rawValue.lowercased() ?? ""
            guard key.hasSuffix("metadata_block_picture") || key.hasSuffix("apic") || key.hasSuffix("covr")
                    || key == "common/artwork",
                  let data = try? await item.load(.dataValue) else { continue }
            if let image = NSImage(data: data) { return image }
            if let inner = FLACPicture.imageData(data), let image = NSImage(data: inner) { return image }
        }
        return folderCover(url.deletingLastPathComponent())
    }

    static func folderCover(_ folder: URL) -> NSImage? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let images = names.filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
        let preferred = ["cover", "folder", "front", "albumart"]
        let best = images.first { name in
            preferred.contains { (name as NSString).deletingPathExtension.lowercased().hasPrefix($0) }
        } ?? images.first
        return best.flatMap { NSImage(contentsOf: folder.appendingPathComponent($0)) }
    }

    private static func formatName(_ id: AudioFormatID, extension ext: String) -> String {
        switch id {
        case kAudioFormatFLAC: "FLAC"
        case kAudioFormatMPEGLayer3: "MP3"
        case kAudioFormatAppleLossless: "ALAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE: "AAC"
        case kAudioFormatLinearPCM: ext.lowercased() == "wav" ? "WAV" : "AIFF"
        default: ext.uppercased()
        }
    }

    /// Bits per sample. FLAC and ALAC say it in their flags (1 = 16 bits,
    /// 2 = 20, 3 = 24, 4 = 32); plain PCM in its bits per channel.
    private static func bits(_ description: AudioStreamBasicDescription) -> Int? {
        switch description.mFormatID {
        case kAudioFormatFLAC, kAudioFormatAppleLossless:
            [1: 16, 2: 20, 3: 24, 4: 32][description.mFormatFlags]
        case kAudioFormatLinearPCM:
            description.mBitsPerChannel > 0 ? Int(description.mBitsPerChannel) : nil
        default: nil
        }
    }
}

import SwiftUI

/// A 5×7 dot font, the kind a hi-fi player's fluorescent display (VFD)
/// draws with: every character is a grid of round dots, lit or unlit.
/// The look comes from a Denon reference photo.
enum DotFont {
    static let columns = 5
    static let rows = 7

    /// The seven rows of a character, each a 5-bit mask (bit 4 is the left dot).
    static func glyph(for character: Character) -> [UInt8] {
        if let rows = table[character] { return rows }
        // Accents fold to the plain letter (á → a), like real players do.
        let folded = String(character).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        if let first = folded.first, let rows = table[first] { return rows }
        return table["?"]!
    }

    /// Text ready to draw: typographic marks become their plain forms.
    static func normalize(_ text: String) -> [Character] {
        var out: [Character] = []
        for character in text {
            switch character {
            case "–", "—", "‐": out.append("-")
            case "…": out.append(contentsOf: "...")
            case "‘", "’", "´": out.append("'")
            case "“", "”", "«", "»": out.append("\"")
            default: out.append(character)
            }
        }
        return out
    }

    private static let table: [Character: [UInt8]] = {
        var table: [Character: [UInt8]] = [:]
        for (character, pattern) in patterns {
            table[character] = pattern.split(separator: " ").map { row in
                row.reduce(UInt8(0)) { ($0 << 1) | ($1 == "#" ? 1 : 0) }
            }
        }
        return table
    }()

    // Classic character-LCD shapes, written row by row: "#" lit, "." unlit.
    private static let patterns: [Character: String] = [
        " ": "..... ..... ..... ..... ..... ..... .....",
        "!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
        "¡": "..#.. ..... ..#.. ..#.. ..#.. ..#.. ..#..",
        "\"": ".#.#. .#.#. .#.#. ..... ..... ..... .....",
        "#": ".#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.",
        "$": "..#.. .#### #.#.. .###. ..#.# ####. ..#..",
        "%": "##... ##..# ...#. ..#.. .#... #..## ...##",
        "&": ".##.. #..#. #.#.. .#... #.#.# #..#. .##.#",
        "'": ".##.. ..#.. .#... ..... ..... ..... .....",
        "(": "...#. ..#.. .#... .#... .#... ..#.. ...#.",
        ")": ".#... ..#.. ...#. ...#. ...#. ..#.. .#...",
        "*": "..... ..#.. #.#.# .###. #.#.# ..#.. .....",
        "+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
        ",": "..... ..... ..... ..... .##.. ..#.. .#...",
        "-": "..... ..... ..... ##### ..... ..... .....",
        ".": "..... ..... ..... ..... ..... .##.. .##..",
        "/": "..... ....# ...#. ..#.. .#... #.... .....",
        "0": ".###. #...# #..## #.#.# ##..# #...# .###.",
        "1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
        "2": ".###. #...# ....# ...#. ..#.. .#... #####",
        "3": "##### ...#. ..#.. ...#. ....# #...# .###.",
        "4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
        "5": "##### #.... ####. ....# ....# #...# .###.",
        "6": "..##. .#... #.... ####. #...# #...# .###.",
        "7": "##### ....# ...#. ..#.. .#... .#... .#...",
        "8": ".###. #...# #...# .###. #...# #...# .###.",
        "9": ".###. #...# #...# .#### ....# ...#. .##..",
        ":": "..... .##.. .##.. ..... .##.. .##.. .....",
        ";": "..... .##.. .##.. ..... .##.. ..#.. .#...",
        "<": "...#. ..#.. .#... #.... .#... ..#.. ...#.",
        "=": "..... ..... ##### ..... ##### ..... .....",
        ">": ".#... ..#.. ...#. ....# ...#. ..#.. .#...",
        "?": ".###. #...# ....# ...#. ..#.. ..... ..#..",
        "¿": "..#.. ..... ..#.. .#... #.... #...# .###.",
        "@": ".###. #...# ....# .##.# #.#.# #.#.# .###.",
        "A": ".###. #...# #...# ##### #...# #...# #...#",
        "B": "####. #...# #...# ####. #...# #...# ####.",
        "C": ".###. #...# #.... #.... #.... #...# .###.",
        "D": "###.. #..#. #...# #...# #...# #..#. ###..",
        "E": "##### #.... #.... ####. #.... #.... #####",
        "F": "##### #.... #.... ####. #.... #.... #....",
        "G": ".###. #...# #.... #.### #...# #...# .####",
        "H": "#...# #...# #...# ##### #...# #...# #...#",
        "I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
        "J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
        "K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
        "L": "#.... #.... #.... #.... #.... #.... #####",
        "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
        "N": "#...# #...# ##..# #.#.# #..## #...# #...#",
        "Ñ": ".##.# #..#. #...# ##..# #.#.# #..## #...#",
        "O": ".###. #...# #...# #...# #...# #...# .###.",
        "P": "####. #...# #...# ####. #.... #.... #....",
        "Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
        "R": "####. #...# #...# ####. #.#.. #..#. #...#",
        "S": ".#### #.... #.... .###. ....# ....# ####.",
        "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
        "U": "#...# #...# #...# #...# #...# #...# .###.",
        "V": "#...# #...# #...# #...# #...# .#.#. ..#..",
        "W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
        "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
        "Y": "#...# #...# #...# .#.#. ..#.. ..#.. ..#..",
        "Z": "##### ....# ...#. ..#.. .#... #.... #####",
        "[": ".###. .#... .#... .#... .#... .#... .###.",
        "\\": "..... #.... .#... ..#.. ...#. ....# .....",
        "]": ".###. ...#. ...#. ...#. ...#. ...#. .###.",
        "^": "..#.. .#.#. #...# ..... ..... ..... .....",
        "_": "..... ..... ..... ..... ..... ..... #####",
        "`": ".#... ..#.. ...#. ..... ..... ..... .....",
        "a": "..... ..... .###. ....# .#### #...# .####",
        "b": "#.... #.... #.##. ##..# #...# #...# ####.",
        "c": "..... ..... .###. #.... #.... #...# .###.",
        "d": "....# ....# .##.# #..## #...# #...# .####",
        "e": "..... ..... .###. #...# ##### #.... .###.",
        "f": "..##. .#..# .#... ###.. .#... .#... .#...",
        "g": "..... .#### #...# #...# .#### ....# .###.",
        "h": "#.... #.... #.##. ##..# #...# #...# #...#",
        "i": "..#.. ..... .##.. ..#.. ..#.. ..#.. .###.",
        "j": "...#. ..... ..##. ...#. ...#. #..#. .##..",
        "k": "#.... #.... #..#. #.#.. ##... #.#.. #..#.",
        "l": ".##.. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
        "m": "..... ..... ##.#. #.#.# #.#.# #...# #...#",
        "n": "..... ..... #.##. ##..# #...# #...# #...#",
        "ñ": ".##.# #..#. ..... #.##. ##..# #...# #...#",
        "o": "..... ..... .###. #...# #...# #...# .###.",
        "p": "..... ..... ####. #...# ####. #.... #....",
        "q": "..... ..... .##.# #..## .#### ....# ....#",
        "r": "..... ..... #.##. ##..# #.... #.... #....",
        "s": "..... ..... .###. #.... .###. ....# ####.",
        "t": ".#... .#... ###.. .#... .#... .#..# ..##.",
        "u": "..... ..... #...# #...# #...# #..## .##.#",
        "v": "..... ..... #...# #...# #...# .#.#. ..#..",
        "w": "..... ..... #...# #...# #.#.# #.#.# .#.#.",
        "x": "..... ..... #...# .#.#. ..#.. .#.#. #...#",
        "y": "..... ..... #...# #...# .#### ....# .###.",
        "z": "..... ..... ##### ...#. ..#.. .#... #####",
        "{": "...#. ..#.. ..#.. .#... ..#.. ..#.. ...#.",
        "|": "..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
        "}": ".#... ..#.. ..#.. ...#. ..#.. ..#.. .#...",
        "~": "..... ..... .#... #.#.# ...#. ..... .....",
        "★": "..#.. ..#.. ##### .###. .#.#. #...# .....",
        "▶": "#.... ##... ###.. ####. ###.. ##... #....",
        "‖": "..... ##.## ##.## ##.## ##.## ##.## .....",
        "■": "..... ##### ##### ##### ##### ##### .....",
    ]
}

/// One line of the display: a fixed row of character cells drawn as dots.
/// Unlit dots stay faintly visible, like the grid of a real display. A
/// line longer than its cells scrolls one character at a time when
/// `scrolls` is on, and holds still at the start for a moment.
struct DotLine: View {
    let text: String
    let cells: Int
    var pitch: CGFloat = PlayerTokens.dotPitch
    var color: Color = PlayerTokens.displayText
    var trailing = false
    var scrolls = false

    @State private var start = Date.now

    static func width(cells: Int, pitch: CGFloat) -> CGFloat {
        CGFloat(cells * (DotFont.columns + 1) - 1) * pitch
    }

    var body: some View {
        let characters = DotFont.normalize(text)
        Group {
            if scrolls && characters.count > cells {
                TimelineView(.periodic(from: start, by: PlayerTokens.scrollStep)) { context in
                    DotCanvas(characters: window(of: characters, at: context.date), pitch: pitch, color: color)
                }
            } else {
                DotCanvas(characters: fitted(characters), pitch: pitch, color: color)
            }
        }
        .frame(width: Self.width(cells: cells, pitch: pitch), height: CGFloat(DotFont.rows) * pitch)
        .onChange(of: text) { start = .now }
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    private func fitted(_ characters: [Character]) -> [Character] {
        let cut = Array(characters.prefix(cells))
        let pad = [Character](repeating: " ", count: cells - cut.count)
        return trailing ? pad + cut : cut + pad
    }

    private func window(of characters: [Character], at date: Date) -> [Character] {
        let loop = characters + [Character](repeating: " ", count: PlayerTokens.scrollGap)
        let elapsed = date.timeIntervalSince(start) - PlayerTokens.scrollHold
        let step = elapsed > 0 ? Int(elapsed / PlayerTokens.scrollStep) % loop.count : 0
        return (0..<cells).map { loop[(step + $0) % loop.count] }
    }
}

/// Draws the dots: faint unlit ones, a soft glow, then the lit ones.
private struct DotCanvas: View {
    let characters: [Character]
    let pitch: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, _ in
            let dot = pitch * PlayerTokens.dotFill
            let inset = (pitch - dot) / 2
            var lit = Path()
            var unlit = Path()
            for (index, character) in characters.enumerated() {
                let rows = DotFont.glyph(for: character)
                let left = CGFloat(index * (DotFont.columns + 1)) * pitch
                for row in 0..<DotFont.rows {
                    for column in 0..<DotFont.columns {
                        let rect = CGRect(x: left + CGFloat(column) * pitch + inset,
                                          y: CGFloat(row) * pitch + inset, width: dot, height: dot)
                        if rows[row] & (1 << (DotFont.columns - 1 - column)) != 0 {
                            lit.addEllipse(in: rect)
                        } else {
                            unlit.addEllipse(in: rect)
                        }
                    }
                }
            }
            context.fill(unlit, with: .color(color.opacity(PlayerTokens.dotUnlitOpacity)))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pitch * 1.4))
                glow.fill(lit, with: .color(color.opacity(PlayerTokens.dotGlowOpacity)))
            }
            context.fill(lit, with: .color(color))
        }
    }
}

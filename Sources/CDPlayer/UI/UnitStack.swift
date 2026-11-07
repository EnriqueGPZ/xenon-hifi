import AppKit
import SwiftUI

/// The hi-fi stack: the extra units stand on top of the CD player, each one's
/// feet on the lid of the one below, and they all move as one. AppKit keeps
/// a child window glued to its parent, so every unit becomes the player's
/// child; a drag on any unit drags the player, and the rest come along.
///
/// The order, bottom to top, is fixed: CD player, file player, tube
/// preamp, equalizer (the order the sound goes through them).
/// Opening or closing a unit puts the others back in place.
enum UnitStack {
    /// The units that stand on the player, bottom to top.
    static let order = [FilePlayerView.windowID, TubeView.windowID, EqualizerView.windowID]

    static var player: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    static func unit(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(id) == true }
    }

    /// Stacks every open unit on the player, in order. If the screen has no
    /// room above, the player moves down first.
    static func arrange() {
        guard let player else { return }
        for child in player.childWindows ?? [] { player.removeChildWindow(child) }
        let units = order.compactMap(unit)
        guard !units.isEmpty else { return }
        // Every window keeps a clear margin of Space.lg around its device:
        // overlap the two margins so the feet stand on the lid.
        let overlap = 2 * Space.lg
        let height = units.reduce(0) { $0 + $1.frame.height - overlap }
        if let screen = player.screen?.visibleFrame, player.frame.maxY + height > screen.maxY {
            let down = player.frame.maxY + height - screen.maxY
            player.setFrameOrigin(NSPoint(x: player.frame.minX, y: max(screen.minY, player.frame.minY - down)))
        }
        var lid = player.frame.maxY
        for unit in units {
            unit.setFrameOrigin(NSPoint(x: (player.frame.midX - unit.frame.width / 2).rounded(), y: lid - overlap))
            lid = unit.frame.maxY
            unit.level = player.level
            player.addChildWindow(unit, ordered: .above)
        }
    }

    /// A unit closed: the ones above it come down. Waits a moment, so the
    /// closing window is no longer counted as visible.
    static func unitClosed() {
        DispatchQueue.main.async { arrange() }
    }

    /// Moves the whole stack with the mouse, from a drag that started on a unit.
    static func dragStack() {
        guard let event = NSApp.currentEvent, let window = player ?? event.window else { return }
        window.performDrag(with: event)
    }
}

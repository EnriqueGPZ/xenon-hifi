import SwiftUI

/// The XENON badge at the top left of every unit: polished chrome letters
/// and a disc emblem. Now and then a glint of light runs across the metal,
/// and while the pointer is over it the glint follows the pointer, as a
/// lamp moving over a real front would.
struct BrandLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the glint stands, as a share of the badge's width; off the
    /// badge below 0 or above 1.
    @State private var glint = BrandLogo.pinned ?? PlayerTokens.glintOff.lowerBound
    @State private var following = false

    var body: some View {
        mark
            .foregroundStyle(PlayerTokens.chrome)
            // Light adds to the metal: the glint brightens what it crosses.
            .overlay { shine.mask(mark).blendMode(.plusLighter).allowsHitTesting(false) }
            .overlay { hoverArea }
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel("Xenon")
            .task { await glintNowAndThen() }
    }

    private var mark: some View {
        HStack(spacing: Space.sm) {
            ZStack {
                Circle().stroke(lineWidth: PlayerTokens.emblemRing)
                Circle().stroke(lineWidth: PlayerTokens.emblemInnerRing)
                    .padding(PlayerTokens.emblemSize * 0.25)
                // The hub, one bright dot (the chrome bands would make it a dash).
                Circle().fill(PlayerTokens.chromeHub)
                    .frame(width: PlayerTokens.emblemSize * 0.2, height: PlayerTokens.emblemSize * 0.2)
            }
            .frame(width: PlayerTokens.emblemSize, height: PlayerTokens.emblemSize)
            Text("XENON")
                .font(PlayerTokens.brandFont)
                .tracking(PlayerTokens.brandTracking)
        }
    }

    private var shine: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let band = width * PlayerTokens.glintWidth
            LinearGradient(colors: [.clear, PlayerTokens.chromeGlint, .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: glint * width - band / 2) // grid: ok the moving glint, not layout
        }
    }

    private var hoverArea: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        following = true
                        withAnimation(.easeOut(duration: PlayerTokens.glintFollow)) {
                            glint = point.x / max(proxy.size.width, 1)
                        }
                    case .ended:
                        following = false
                        withAnimation(.easeIn(duration: PlayerTokens.glintFollow * 4)) {
                            glint = PlayerTokens.glintOff.upperBound
                        }
                    }
                }
        }
    }

    /// Snapshots only: APP_GLINT=0.5 holds the glint there, to look at it.
    private static let pinned: CGFloat? = Store.isOverridden
        ? ProcessInfo.processInfo.environment["APP_GLINT"].flatMap(Double.init).map { CGFloat($0) } : nil

    /// Once when the unit is switched on, then every so often.
    private func glintNowAndThen() async {
        guard !reduceMotion, Self.pinned == nil else { return }
        try? await Task.sleep(for: .seconds(PlayerTokens.glintFirst))
        while !Task.isCancelled {
            if !following {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { glint = PlayerTokens.glintOff.lowerBound }
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeInOut(duration: PlayerTokens.glintSweep)) {
                    glint = PlayerTokens.glintOff.upperBound
                }
            }
            try? await Task.sleep(for: .seconds(PlayerTokens.glintEvery))
        }
    }
}

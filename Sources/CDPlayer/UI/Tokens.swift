import SwiftUI

/// Custom hi-fi look, not Apple's system style: the goal is an app
/// that looks like a real CD player (docs/BRIEF.md, "Look"). Every color,
/// font, and size of the device lives here so views never hard-code one.
enum PlayerTokens {
    // Panel: brushed dark metal.
    static let panelTop = Color(hex: 0x34353A)
    static let panelBottom = Color(hex: 0x18191C)
    static let panelEdge = Color(hex: 0x08090A)
    static let panelHighlight = Color.white.opacity(0.10)
    static let brushLine = Color.white
    static let panelRadius: CGFloat = 6

    // Engraved text on the panel.
    static let engraved = Color(hex: 0x8E8F95)
    static let engravedDim = Color(hex: 0x66676D)
    static let labelFont = Font.system(size: 7.5, weight: .medium)
    static let brandFont = Font.custom("Futura", size: 17).weight(.medium)
    static let brandTracking: CGFloat = 5

    // The XENON badge: polished chrome that catches a glint of light.
    static let chrome = LinearGradient(stops: [
        .init(color: Color(hex: 0xF4F4F6), location: 0),
        .init(color: Color(hex: 0xB9BBC0), location: 0.40),
        .init(color: Color(hex: 0x5D5F65), location: 0.53),
        .init(color: Color(hex: 0xD8D9DC), location: 0.72),
        .init(color: Color(hex: 0x8E9096), location: 1),
    ], startPoint: .top, endPoint: .bottom)
    static let chromeGlint = Color.white.opacity(0.95)
    static let chromeHub = Color(hex: 0xD8D9DC)
    static let emblemSize: CGFloat = 18
    static let emblemRing: CGFloat = 1.6
    static let emblemInnerRing: CGFloat = 1.1
    /// The glint: its width as a share of the badge, where it rests off the
    /// badge, how long a pass takes, and how often it passes on its own.
    static let glintWidth: CGFloat = 0.22
    static let glintOff: ClosedRange<CGFloat> = -0.3...1.3
    static let glintSweep: Double = 1.6
    static let glintFirst: Double = 0.8
    static let glintEvery: Double = 25
    static let glintFollow: Double = 0.15
    static let modelFont = Font.system(size: 7.5, weight: .regular)

    // Disc tray slot.
    static let trayTop = Color(hex: 0x050506)
    static let trayBottom = Color(hex: 0x1B1C1F)

    // Disc tray door.
    static let doorTop = Color(hex: 0x2C2D31)
    static let doorBottom = Color(hex: 0x1A1B1E)
    static let doorHeight: CGFloat = 20

    // Fluorescent dot-matrix display (VFD): black glass, aqua dots.
    static let displayBackground = Color(hex: 0x020504)
    static let displayText = Color(hex: 0x86FBE0)
    static let displayTextDim = Color(hex: 0x4FB59C)
    static let displayGhost = Color(hex: 0x86FBE0).opacity(0.13)
    static let displayGlow = Color(hex: 0x86FBE0).opacity(0.45)
    static let glassReflection = Color.white.opacity(0.07)
    static let displayWidth: CGFloat = 448
    static let displayRadius: CGFloat = 3
    static let bezelRadius: CGFloat = 6
    static let bezelTop = Color(hex: 0x0A0A0B)
    static let bezelBottom = Color(hex: 0x1E1F22)
    /// Distance between dot centers, by text size.
    static let dotPitchSmall: CGFloat = 1.5
    static let dotPitch: CGFloat = 2
    static let dotPitchTitle: CGFloat = 2.5
    static let dotPitchLarge: CGFloat = 4
    /// Dot diameter as a share of the pitch.
    static let dotFill: CGFloat = 0.78
    static let dotUnlitOpacity: Double = 0.018
    static let dotGlowOpacity: Double = 0.55
    /// Scrolling text moves one character per step, after a hold at the start.
    static let scrollStep: Double = 0.32
    static let scrollHold: Double = 2
    static let scrollGap = 4
    /// Spectrum bars: dots across each bar, and the red line under them.
    static let spectrumBarDots = 4
    static let spectrumBase = Color(hex: 0xFF4A3D)

    // VU meters: black faces lit from behind by a warm lamp, gold scale,
    // red above 0 VU, a pale needle.
    static let vuFaceTop = Color(hex: 0x0B0A08)
    static let vuFaceBottom = Color(hex: 0x050505)
    static let vuLamp = Color(hex: 0xFFB347).opacity(0.16)
    static let vuScale = Color(hex: 0xE9B949)
    static let vuRed = Color(hex: 0xE5482F)
    static let vuNeedle = Color(hex: 0xF3EEE2)
    static let vuNeedleShadow = Color.black.opacity(0.6)
    static let vuRadius: CGFloat = 3
    static let vuLine: CGFloat = 0.8
    static let vuBand: CGFloat = 2.2
    static let vuTick: CGFloat = 0.9
    static let vuTickMinor: CGFloat = 0.6
    static let vuNeedleWidth: CGFloat = 1.1
    static let vuNumberFont = Font.system(size: 6.5, weight: .semibold)
    static let vuNameFont = Font.system(size: 10, weight: .bold)
    static let vuChannelFont = Font.system(size: 6.5, weight: .semibold)
    /// Half the needle's swing, in degrees either side of upright.
    static let vuSwing: Double = 46

    // Buttons and the volume knob: spun metal discs set in the front.
    static let buttonFaceLight = Color(hex: 0x48494E)
    static let buttonFaceDark = Color(hex: 0x151619)
    static let buttonRimLight = Color.white.opacity(0.28)
    static let collarTop = Color(hex: 0x050506)
    static let collarBottom = Color(hex: 0x2B2C30)
    static let buttonIcon = Color(hex: 0xDADADF)
    static let buttonPressed = Color.black.opacity(0.30)
    static let knobIndicator = Color(hex: 0xF2F2F4)
    static let knobTick = Color(hex: 0x8A8B91)
    static let buttonSmall: CGFloat = 32
    static let buttonMedium: CGFloat = 40
    static let buttonLarge: CGFloat = 48
    static let knobSize: CGFloat = 68
    /// Drag for one click of a selector knob.
    static let knobDetent: CGFloat = 10
    /// Holding |<< or >>| scans the song: after this wait, a step each repeat.
    static let holdDelay: Double = 0.4
    static let holdRepeat: Double = 0.15
    static let balanceKnobSize: CGFloat = 44
    static let collarWidth: CGFloat = 3

    // Symbols printed on the front above the buttons.
    static let printFont = Font.system(size: 6.5, weight: .semibold)

    // Pilot lights beside the mode names.
    static let modeLightOn = Color(hex: 0x86FBE0)
    static let modeLightOff = Color(hex: 0x0E1412)
    static let modeLightGlow = Color(hex: 0x86FBE0).opacity(0.8)
    static let modeLightSize: CGFloat = 4

    // Side cheeks: the darker end caps of the case.
    static let cheekLight = Color(hex: 0x2A2B2F)
    static let cheekDark = Color(hex: 0x0C0D0F)
    static let cheekWidth: CGFloat = 12

    // Power LED.
    static let ledOn = Color(hex: 0x4BE37A)
    static let ledGlow = Color(hex: 0x4BE37A).opacity(0.8)
    static let ledSize: CGFloat = 6

    // Graphic equalizer unit: faders in slots cut into the front, a dot
    // curve and peak meters on its display, a red OVER light per channel.
    static let faderHeight: CGFloat = 120
    static let faderSlotWidth: CGFloat = 4
    static let faderCapWidth: CGFloat = 20
    static let faderCapHeight: CGFloat = 12
    static let faderCapLine = Color(hex: 0xF2F2F4)
    static let faderTickLong: CGFloat = 5
    static let faderTickShort: CGFloat = 3
    static let faderTickWidth: CGFloat = 0.8
    static let faderDragRange: CGFloat = 108
    static let eqCurveHeight: CGFloat = 52
    static let eqMeterHeight: CGFloat = 6
    static let eqOver = Color(hex: 0xFF4A3D)
    static let eqZeroLine = Color(hex: 0x86FBE0).opacity(0.22)

    // File player unit: a colour screen for the cover, the rest kept as
    // plain as the other units. Gold for the sound's quality, like the VU scale.
    static let screenBackground = Color(hex: 0x050506)
    static let screenText = Color(hex: 0xF2F2F4)
    static let screenTextDim = Color(hex: 0x9A9BA1)
    static let screenTextFaint = Color(hex: 0x5E5F65)
    static let screenAccent = Color(hex: 0xE9B949)
    static let screenTrack = Color(hex: 0x2A2B2F)
    static let screenHeight: CGFloat = 168
    static let coverSize: CGFloat = 144
    static let coverRadius: CGFloat = 2
    static let progressHeight: CGFloat = 2
    static let listRowHeight: CGFloat = 18
    static let screenTitleFont = Font.system(size: 15, weight: .semibold)
    static let screenArtistFont = Font.system(size: 12, weight: .regular)
    static let screenAlbumFont = Font.system(size: 11, weight: .regular)
    static let screenQualityFont = Font.system(size: 9, weight: .semibold)
    static let screenTimeFont = Font.system(size: 9, weight: .medium).monospacedDigit()

    // Tube preamp unit: four glass tubes behind a window cut in the front,
    // their filaments glowing amber, brighter with the sound.
    static let tubeWindowHeight: CGFloat = 156
    static let tubeWindowTop = Color(hex: 0x0B0908)
    static let tubeWindowBottom = Color(hex: 0x030303)
    static let tubeFloor = Color(hex: 0x1A1714)
    static let tubeFloorHeight: CGFloat = 8
    /// Small tubes (ECC88 size) at the ends, tall ones in the middle.
    static let tubeSmallHeight: CGFloat = 112
    static let tubeLargeHeight: CGFloat = 144
    /// The filament light: how far its bloom spreads, how strong the bloom
    /// is, and how much the light itself is lifted at full glow.
    static let tubeBloom: CGFloat = 6
    /// The drawn base of the tall tubes, as shares of the tube's height.
    static let tubeBaseWidth: CGFloat = 0.19
    static let tubeBaseHeight: CGFloat = 0.25
    static let tubeSocketTop = Color(hex: 0x34302B)
    static let tubeSocketBottom = Color(hex: 0x0C0B0A)
    static let tubeBloomStrength = 0.9
    static let tubeLightGain = 1.25
    static let tubeHalo = Color(hex: 0xFF8C2E)
    static let tubeFloorGlow = Color(hex: 0xFF8C2E)
    /// The pilot light of the VÁLVULAS switch: amber, like the filaments.
    static let tubeLampOn = Color(hex: 0xFFB347)
    static let tubeLampGlow = Color(hex: 0xFFB347).opacity(0.85)
    /// How much brighter or dimmer each tube burns: no two tubes are equal.
    static let tubeVariance: [Double] = [0.96, 1.04, 1, 0.94]

    // Feet under the device.
    static let footTop = Color(hex: 0x3A3B40)
    static let footBottom = Color(hex: 0x0E0F11)
    static let footWidth: CGFloat = 96
    static let footHeight: CGFloat = 16
}

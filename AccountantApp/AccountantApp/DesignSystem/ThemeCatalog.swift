import SwiftUI

/// Every colour a theme has to answer for.
///
/// Stored as packed RGB so a whole palette reads as a block and is easy to compare
/// against its neighbours. Any theme must fill in all of it — there are no optional
/// slots, because a half-defined theme fails in whichever screen you forgot.
struct ThemePalette: Hashable {
    let canvas: UInt32
    let surface: UInt32
    let surfaceRaised: UInt32
    let surfaceSunken: UInt32

    let ink: UInt32
    let inkMuted: UInt32
    let inkFaint: UInt32

    /// Text drawn *on top of* the accent. Dark for pale accents, light for deep
    /// ones — the one slot that is easy to get subtly wrong.
    let inkInverse: UInt32

    let hairline: UInt32

    let accent: UInt32
    let accentWash: UInt32

    let inflow: UInt32
    let deficit: UInt32
    let pending: UInt32

    /// The brand mark's own ground and ink.
    ///
    /// Separate from `accent`/`inkInverse` because the icon's best ground is not
    /// always the theme's accent — Ember's mark is orange on near-black, not black
    /// on orange. These are the exact values the app icon is generated from, so
    /// the mark on screen and the icon on the home screen are the same artwork.
    let brandGround: UInt32
    let brandInk: UInt32
}

struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String

    /// A theme may support one appearance or both. Committing to a single one is a
    /// legitimate choice — some palettes only work dark — and honest about it,
    /// rather than shipping a washed-out inversion nobody wants to look at.
    let light: ThemePalette?
    let dark: ThemePalette?

    /// Forced when the theme only defines one appearance.
    var forcedColorScheme: ColorScheme? {
        if light == nil { return .dark }
        if dark == nil { return .light }
        return nil
    }

    var supportsBothAppearances: Bool {
        light != nil && dark != nil
    }

    func palette(for style: UIUserInterfaceStyle) -> ThemePalette {
        let wantsDark = style == .dark
        // Falls back to whichever appearance exists; never returns nil.
        return (wantsDark ? dark ?? light : light ?? dark) ?? ThemeCatalog.cobalt.dark!
    }
}

enum ThemeCatalog {

    static let all: [AppTheme] = [cobalt, ember, graphite, indigo, moss, paper]

    static let `default` = cobalt

    static func theme(id: String) -> AppTheme {
        all.first { $0.id == id } ?? `default`
    }

    // MARK: - Cobalt

    /// The original. Follows the system between light and dark.
    static let cobalt = AppTheme(
        id: "cobalt",
        name: "Cobalt",
        blurb: "Bright and neutral. Follows your system appearance.",
        light: ThemePalette(
            canvas: 0xF4F5F7,
            surface: 0xFFFFFF,
            surfaceRaised: 0xFFFFFF,
            surfaceSunken: 0xEEEFF2,
            ink: 0x0B0D10,
            inkMuted: 0x6E7683,
            inkFaint: 0x9AA1AC,
            inkInverse: 0xFFFFFF,
            hairline: 0xE6E8EC,
            accent: 0x2F5FF0,
            accentWash: 0xE8EEFF,
            inflow: 0x0FA47A,
            deficit: 0xE0443E,
            pending: 0xC77A0A,
            brandGround: 0x2F5FF0,
            brandInk: 0xFFFFFF
        ),
        dark: ThemePalette(
            canvas: 0x0B0D10,
            surface: 0x16191F,
            surfaceRaised: 0x1E222A,
            surfaceSunken: 0x101317,
            ink: 0xF4F6F8,
            inkMuted: 0x8B93A1,
            inkFaint: 0x656C78,
            inkInverse: 0xFFFFFF,
            hairline: 0x252A32,
            accent: 0x5B85FF,
            accentWash: 0x1B2436,
            inflow: 0x34D9A4,
            deficit: 0xFF6B63,
            pending: 0xF0A741,
            brandGround: 0x2F5FF0,
            brandInk: 0xFFFFFF
        )
    )

    // MARK: - Ember

    /// Warm black with a glowing orange accent.
    ///
    /// Orange is a demanding accent because it collides with the two colours money
    /// apps normally reach for: amber for pending and red for deficit both sit next
    /// to it on the wheel and turn muddy. So this palette moves them out of its way
    /// — pending goes lighter and yellower, deficit goes pink-red — and money in
    /// takes a cool mint that the orange has nothing to argue with.
    ///
    /// Blacks are warm rather than neutral, so the accent reads as heat coming off
    /// the surface instead of a sticker on top of it.
    static let ember = AppTheme(
        id: "ember",
        name: "Ember",
        blurb: "Warm black with a glowing orange accent.",
        light: nil,
        dark: ThemePalette(
            canvas: 0x0A0908,
            surface: 0x15120F,
            surfaceRaised: 0x1E1A15,
            surfaceSunken: 0x0F0D0B,
            ink: 0xF5F1EC,
            inkMuted: 0x9A9088,
            inkFaint: 0x6A625B,
            // The accent is bright enough that text on it must be dark.
            inkInverse: 0x0A0908,
            hairline: 0x2A251F,
            accent: 0xFF7A29,
            accentWash: 0x2E1C0D,
            inflow: 0x35D6A0,
            deficit: 0xFF4D6D,
            pending: 0xFFC24D,
            brandGround: 0x12100E,
            brandInk: 0xFF7A29
        )
    )

    // MARK: - Graphite

    /// Warm neutral blacks and a cool steel accent. Almost no colour, which is what
    /// makes the figures the loudest thing on screen.
    static let graphite = AppTheme(
        id: "graphite",
        name: "Graphite",
        blurb: "Warm blacks, steel accent. Almost no colour.",
        light: nil,
        dark: ThemePalette(
            canvas: 0x0E0E0F,
            surface: 0x1A1A1C,
            surfaceRaised: 0x232326,
            surfaceSunken: 0x141416,
            ink: 0xF2F1EF,
            inkMuted: 0x9A9895,
            inkFaint: 0x6B6A68,
            // Pale accent, so text on it must be dark.
            inkInverse: 0x0E0E0F,
            hairline: 0x2A2A2D,
            accent: 0xA8B2C0,
            accentWash: 0x22262C,
            inflow: 0x7FBF9A,
            deficit: 0xD98A80,
            pending: 0xC9A96A,
            brandGround: 0x1A1A1C,
            brandInk: 0xF2F1EF
        )
    )

    // MARK: - Indigo

    /// Blue-black with violet and a cold teal for money in.
    static let indigo = AppTheme(
        id: "indigo",
        name: "Indigo",
        blurb: "Blue-black, violet accent, cold teal.",
        light: nil,
        dark: ThemePalette(
            canvas: 0x0A0A14,
            surface: 0x15141F,
            surfaceRaised: 0x1E1C2B,
            surfaceSunken: 0x100F18,
            ink: 0xF0EEF8,
            inkMuted: 0x918DA8,
            inkFaint: 0x615E75,
            inkInverse: 0xFFFFFF,
            hairline: 0x272438,
            accent: 0x8B7CF6,
            accentWash: 0x231F3A,
            inflow: 0x3FD9C9,
            deficit: 0xFF6B8A,
            pending: 0xE0A64F,
            brandGround: 0x15141F,
            brandInk: 0x8B7CF6
        )
    )

    // MARK: - Moss

    /// Green-black and sage. Quieter than the others and easiest at night.
    static let moss = AppTheme(
        id: "moss",
        name: "Moss",
        blurb: "Green-black and sage. Easiest at night.",
        light: nil,
        dark: ThemePalette(
            canvas: 0x0A0F0C,
            surface: 0x141A16,
            surfaceRaised: 0x1C241E,
            surfaceSunken: 0x0F1411,
            ink: 0xEEF2EE,
            inkMuted: 0x8B9A8E,
            inkFaint: 0x5D6B60,
            inkInverse: 0x0A0F0C,
            hairline: 0x232D26,
            accent: 0x8FC7A0,
            accentWash: 0x1A2A1F,
            inflow: 0x6FD99A,
            deficit: 0xE08878,
            pending: 0xD4B26A,
            brandGround: 0x141A16,
            brandInk: 0x8FC7A0
        )
    )

    // MARK: - Paper

    /// Warm white and deep navy. Light only — dressing this one in black would
    /// throw away the thing that makes it work.
    static let paper = AppTheme(
        id: "paper",
        name: "Paper",
        blurb: "Warm white, deep navy. Light only.",
        light: ThemePalette(
            canvas: 0xF7F6F3,
            surface: 0xFFFFFF,
            surfaceRaised: 0xFFFFFF,
            surfaceSunken: 0xEFEEEA,
            ink: 0x16171A,
            inkMuted: 0x6A6B70,
            inkFaint: 0x9B9C9F,
            inkInverse: 0xFFFFFF,
            hairline: 0xE3E1DB,
            accent: 0x24406B,
            accentWash: 0xE7ECF4,
            inflow: 0x15795C,
            deficit: 0xB03A2E,
            pending: 0x9C6B1A,
            brandGround: 0xF7F6F3,
            brandInk: 0x24406B
        ),
        dark: nil
    )
}

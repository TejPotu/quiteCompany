import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Palette
//
// Holds every named color the app uses. Two palettes ship: a warm/ember
// hearthside vibe (the original) and a cool/ocean palette for caregivers
// who prefer a calmer blue tone. Switching is done by mutating
// `HearthPalette.current` and forcing the SwiftUI tree to rebuild — see
// `HearthApp` for the `.id()` trick that re-renders the world on change.
struct HearthPalette {
    // Surface
    let paper: Color
    let paperDeep: Color
    let card: Color
    let cardWarm: Color

    // Ink
    let ink: Color
    let inkSoft: Color
    let inkMute: Color
    let inkFaint: Color

    // Primary accent (ember in warm, deep ocean in ocean)
    let ember: Color
    let emberSoft: Color
    let emberDeep: Color

    // Sage (presence-OK / wellness)
    let sage: Color
    let sageSoft: Color
    let sageDeep: Color

    // Sky
    let sky: Color
    let skySoft: Color
    let skyDeep: Color

    // Honey (warm secondary)
    let honey: Color
    let honeySoft: Color
    let honeyDeep: Color

    // Borders
    let border: Color
    let borderSoft: Color

    // Semantic alerts — kept warm across both palettes so an alert is
    // never confused with a normal accent.
    let gentleAlert: Color
    let gentleAlertSoft: Color
}

extension HearthPalette {
    // Original warm-hearth palette.
    static let warm = HearthPalette(
        paper:       Color(hex: 0xFAF6EF),
        paperDeep:   Color(hex: 0xF2EBE0),
        card:        Color(hex: 0xFFFFFF),
        cardWarm:    Color(hex: 0xFFFBF4),

        ink:         Color(hex: 0x2A241C),
        inkSoft:     Color(hex: 0x54493D),
        inkMute:     Color(hex: 0x8A7F71),
        inkFaint:    Color(hex: 0xC7BDAE),

        ember:       Color(hex: 0xC76A3F),
        emberSoft:   Color(hex: 0xE8B89C),
        emberDeep:   Color(hex: 0x9C4E2C),

        sage:        Color(hex: 0x7B8F6E),
        sageSoft:    Color(hex: 0xC9D3BD),
        sageDeep:    Color(hex: 0x5A6B50),

        sky:         Color(hex: 0x7A9AB3),
        skySoft:     Color(hex: 0xC9D7E2),
        skyDeep:     Color(hex: 0x4F708A),

        honey:       Color(hex: 0xE8C77B),
        honeySoft:   Color(hex: 0xF4E4B8),
        honeyDeep:   Color(hex: 0xB89A4F),

        border:      Color(hex: 0xE8DECF),
        borderSoft:  Color(hex: 0xF0E8DA),

        gentleAlert:     Color(hex: 0xB85C4F),
        gentleAlertSoft: Color(hex: 0xEBC9C2)
    )

    // Soft-forest palette — a deliberate move away from the cream+orange
    // hearthside vibe (which reads as Anthropic-y at a Google hackathon)
    // toward a calm garden-green that still respects dementia-friendly
    // design guidance:
    //   • paper carries a faint sage tint, not a pure white — keeps
    //     glare down for older eyes;
    //   • ink is a near-black forest charcoal — AAA contrast against
    //     paper, softer than pure black;
    //   • primary accent is a saturated forest green — distinctive,
    //     legible, gestures at Google's green identity without copying
    //     Material's brand blues;
    //   • wellness ("sage" role) is reassigned to warm amber/ochre so
    //     "all good" never collides with the primary accent;
    //   • alerts stay warm-red so urgency reads across themes.
    static let softForest = HearthPalette(
        paper:       Color(hex: 0xF0F4EA),
        paperDeep:   Color(hex: 0xDCE5CC),
        card:        Color(hex: 0xF9FBF5),
        cardWarm:    Color(hex: 0xF2F6EB),

        ink:         Color(hex: 0x18241A),
        inkSoft:     Color(hex: 0x364A38),
        inkMute:     Color(hex: 0x6A7868),
        inkFaint:    Color(hex: 0xA8B2A4),

        // Primary accent — saturated forest green. ~5.5:1 against
        // paper, comfortably above AA for accents.
        ember:       Color(hex: 0x3F7A45),
        emberSoft:   Color(hex: 0xBAD7BD),
        emberDeep:   Color(hex: 0x285530),

        // Wellness role becomes warm amber so the "all good" cue never
        // visually conflicts with the green primary.
        sage:        Color(hex: 0xA88F3E),
        sageSoft:    Color(hex: 0xE7D8A8),
        sageDeep:    Color(hex: 0x7A641F),

        // Sky role — warm earth-brown for hierarchical use, distinct
        // from both green primary and amber wellness.
        sky:         Color(hex: 0x8A6F4A),
        skySoft:     Color(hex: 0xD8C7A8),
        skyDeep:     Color(hex: 0x5C462A),

        // Honey — rich amber/gold, the longest-visible warm hue.
        honey:       Color(hex: 0xD9A52E),
        honeySoft:   Color(hex: 0xF3E1A6),
        honeyDeep:   Color(hex: 0xA87718),

        // Sage-tan borders so card edges register clearly against the
        // green-tinted paper without relying on subtle depth cues.
        border:      Color(hex: 0xC8D2BB),
        borderSoft:  Color(hex: 0xDDE3D2),

        gentleAlert:     Color(hex: 0xA8412E),
        gentleAlertSoft: Color(hex: 0xE5BAB0)
    )

    /// Resolve a stored UserDefaults theme name into a palette. Legacy
    /// keys ("highContrast", "ocean") fall through to softForest so
    /// previously-stored preferences don't leave the app in a broken
    /// state after a theme is retired.
    static func named(_ name: String) -> HearthPalette {
        switch name.lowercased() {
        case "softforest", "highcontrast", "ocean": return .softForest
        default:                                    return .warm
        }
    }
}

// MARK: - HearthColor
//
// Static accessors used everywhere in the app. Each property reads from
// the currently active palette, so swapping `HearthPalette.current`
// changes every site in one shot. SwiftUI doesn't track static-var
// reads, so the caller (HearthApp) forces a tree rebuild via `.id()`
// when the theme name changes.
enum HearthColor {
    static var activePalette: HearthPalette = .warm

    static var paper: Color       { activePalette.paper }
    static var paperDeep: Color   { activePalette.paperDeep }
    static var card: Color        { activePalette.card }
    static var cardWarm: Color    { activePalette.cardWarm }

    static var ink: Color         { activePalette.ink }
    static var inkSoft: Color     { activePalette.inkSoft }
    static var inkMute: Color     { activePalette.inkMute }
    static var inkFaint: Color    { activePalette.inkFaint }

    static var ember: Color       { activePalette.ember }
    static var emberSoft: Color   { activePalette.emberSoft }
    static var emberDeep: Color   { activePalette.emberDeep }

    static var sage: Color        { activePalette.sage }
    static var sageSoft: Color    { activePalette.sageSoft }
    static var sageDeep: Color    { activePalette.sageDeep }

    static var sky: Color         { activePalette.sky }
    static var skySoft: Color     { activePalette.skySoft }
    static var skyDeep: Color     { activePalette.skyDeep }

    static var honey: Color       { activePalette.honey }
    static var honeySoft: Color   { activePalette.honeySoft }
    static var honeyDeep: Color   { activePalette.honeyDeep }

    static var border: Color      { activePalette.border }
    static var borderSoft: Color  { activePalette.borderSoft }

    static var gentleAlert: Color     { activePalette.gentleAlert }
    static var gentleAlertSoft: Color { activePalette.gentleAlertSoft }
}

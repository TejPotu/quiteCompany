import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum HearthColor {
    // Surface
    static let paper       = Color(hex: 0xFAF6EF)
    static let paperDeep   = Color(hex: 0xF2EBE0)
    static let card        = Color(hex: 0xFFFFFF)
    static let cardWarm    = Color(hex: 0xFFFBF4)

    // Ink
    static let ink         = Color(hex: 0x2A241C)
    static let inkSoft     = Color(hex: 0x54493D)
    static let inkMute     = Color(hex: 0x8A7F71)
    static let inkFaint    = Color(hex: 0xC7BDAE)

    // Ember
    static let ember       = Color(hex: 0xC76A3F)
    static let emberSoft   = Color(hex: 0xE8B89C)
    static let emberDeep   = Color(hex: 0x9C4E2C)

    // Sage
    static let sage        = Color(hex: 0x7B8F6E)
    static let sageSoft    = Color(hex: 0xC9D3BD)
    static let sageDeep    = Color(hex: 0x5A6B50)

    // Sky
    static let sky         = Color(hex: 0x7A9AB3)
    static let skySoft     = Color(hex: 0xC9D7E2)
    static let skyDeep     = Color(hex: 0x4F708A)

    // Honey
    static let honey       = Color(hex: 0xE8C77B)
    static let honeySoft   = Color(hex: 0xF4E4B8)
    static let honeyDeep   = Color(hex: 0xB89A4F)

    // Borders
    static let border      = Color(hex: 0xE8DECF)
    static let borderSoft  = Color(hex: 0xF0E8DA)

    // Semantic alerts
    static let gentleAlert     = Color(hex: 0xB85C4F)
    static let gentleAlertSoft = Color(hex: 0xEBC9C2)
}

import SwiftUI

enum HearthFont {
    static func serif(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Text {
    func eyebrowStyle() -> some View {
        self.font(HearthFont.sans(size: 16, weight: .bold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(HearthColor.inkMute)
    }
}

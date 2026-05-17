import SwiftUI

// MARK: - Icon
// Bridge from Phosphor names (React) to SF Symbol names (SwiftUI).
enum HearthIcon {
    static func sfName(_ phosphor: String) -> String {
        switch phosphor {
        case "television-simple":       return "tv.fill"
        case "users-three":             return "person.3.fill"
        case "sparkle":                 return "sparkles"
        case "pill":                    return "pill.fill"
        case "check":                   return "checkmark"
        case "check-circle":            return "checkmark.circle.fill"
        case "microphone":              return "mic.fill"
        case "phone":                   return "phone.fill"
        case "coffee":                  return "cup.and.saucer.fill"
        case "fork-knife":              return "fork.knife"
        case "user":                    return "person.fill"
        case "moon":                    return "moon.fill"
        case "heart":                   return "heart.fill"
        case "bookmark-simple":         return "bookmark.fill"
        case "arrow-counter-clockwise": return "arrow.counterclockwise"
        case "play":                    return "play.fill"
        case "pause":                   return "pause.fill"
        case "speaker-high":            return "speaker.wave.3.fill"
        case "x-circle":                return "xmark.circle.fill"
        case "closed-captioning":       return "captions.bubble.fill"
        case "rewind":                  return "backward.fill"
        case "arrow-clockwise":         return "arrow.clockwise"
        case "question":                return "questionmark.circle.fill"
        case "map-pin":                 return "mappin.and.ellipse"
        case "cake":                    return "gift.fill"
        case "camera":                  return "camera.fill"
        case "pencil":                  return "pencil"
        case "plus":                    return "plus"
        case "trash":                   return "trash.fill"
        default:                        return "questionmark"
        }
    }
}

struct Icon: View {
    let name: String
    var size: CGFloat = 32
    var color: Color = HearthColor.ink

    var body: some View {
        Image(systemName: HearthIcon.sfName(name))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Eyebrow
struct Eyebrow: View {
    let text: String
    var color: Color = HearthColor.inkMute
    var body: some View {
        Text(text)
            .font(HearthFont.sans(size: 16, weight: .bold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Photo
enum PhotoTone: Equatable { case ember, sage, sky, honey }

extension PhotoTone {
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .ember: colors = [HearthColor.emberSoft, HearthColor.ember]
        case .sage:  colors = [HearthColor.sageSoft, HearthColor.sage]
        case .sky:   colors = [HearthColor.skySoft, HearthColor.sky]
        case .honey: colors = [HearthColor.honeySoft, HearthColor.honeyDeep]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Button
enum HearthButtonKind { case primary, secondary, confirm, ghost }

struct HearthButton: View {
    let kind: HearthButtonKind
    var icon: String? = nil
    let title: String
    let action: () -> Void

    init(_ title: String, kind: HearthButtonKind = .primary, icon: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.icon = icon
        self.action = action
    }

    private var bg: Color {
        switch kind {
        case .primary:   HearthColor.ember
        case .secondary: HearthColor.paperDeep
        case .confirm:   HearthColor.sage
        case .ghost:     .clear
        }
    }
    private var fg: Color {
        switch kind {
        case .primary, .confirm: .white
        case .secondary, .ghost: HearthColor.ink
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Icon(name: icon, size: 24, color: fg) }
                Text(title)
                    .font(HearthFont.sans(size: 22, weight: .bold))
                    .foregroundStyle(fg)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .frame(minHeight: 64)
            .background(
                Capsule()
                    .fill(bg)
                    .overlay(
                        kind == .ghost
                        ? Capsule().stroke(HearthColor.border, lineWidth: 2)
                        : nil
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Circle button (transport controls on TV)
struct CircleButton: View {
    let icon: String
    var kind: HearthButtonKind = .secondary
    var big: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let diameter: CGFloat = big ? 128 : 96
            let iconSize: CGFloat = big ? 56 : 44
            let bg: Color = (kind == .primary) ? HearthColor.ember : HearthColor.paperDeep
            let fg: Color = (kind == .primary) ? .white : HearthColor.ink
            ZStack {
                Circle().fill(bg)
                Icon(name: icon, size: iconSize, color: fg)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Labeled transport button (icon + word, dementia-friendly)
struct LabeledTransportButton: View {
    let icon: String
    let label: String
    var kind: HearthButtonKind = .secondary
    var big: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let bg: Color = (kind == .primary) ? HearthColor.ember : HearthColor.paperDeep
            let fg: Color = (kind == .primary) ? .white : HearthColor.ink
            HStack(spacing: 12) {
                Icon(name: icon, size: big ? 36 : 28, color: fg)
                Text(label)
                    .font(HearthFont.sans(size: big ? 26 : 22, weight: .bold))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, big ? 32 : 24)
            .padding(.vertical, big ? 20 : 16)
            .frame(minHeight: big ? 88 : 72)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(bg))
            .overlay(
                kind == .secondary
                ? Capsule().stroke(HearthColor.border, lineWidth: 2)
                : nil
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Listening indicator (pulsing dot + label)
struct ListeningIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(HearthColor.ember.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulse ? 1.2 : 0.7)
                    .opacity(pulse ? 0 : 0.3)
                Circle().fill(HearthColor.ember)
                    .frame(width: 14, height: 14)
            }
            Text("Hearth is listening")
                .font(HearthFont.sans(size: 18, weight: .bold))
                .foregroundStyle(HearthColor.inkSoft)
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(HearthColor.card))
        .overlay(Capsule().stroke(HearthColor.borderSoft, lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Weather chip
struct WeatherChip: View {
    let temperature: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HearthColor.ember)
                .symbolRenderingMode(.hierarchical)
            Text(temperature)
                .font(HearthFont.serif(size: 26, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(HearthColor.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(HearthColor.card))
        .overlay(Capsule().stroke(HearthColor.borderSoft, lineWidth: 1))
    }
}

// MARK: - Top bar
struct TopBar: View {
    let greeting: String
    let time: String
    let day: String
    var weatherTemp: String? = nil
    var weatherIcon: String? = nil
    var listening: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(greeting)
                .font(HearthFont.serif(size: 38, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(HearthColor.ink)
            if let temp = weatherTemp, let icon = weatherIcon {
                WeatherChip(temperature: temp, icon: icon)
                    .padding(.leading, 24)
            }
            if listening {
                ListeningIndicator().padding(.leading, 24)
            }
            Spacer(minLength: 0)
            Text(time)
                .font(HearthFont.serif(size: 32, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(HearthColor.inkSoft)
            Text(day)
                .font(HearthFont.sans(size: 18, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(HearthColor.inkMute)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
    }
}

// MARK: - Bottom nav
enum HearthScreen: String, CaseIterable, Identifiable {
    case tv, people, cues
    var id: String { rawValue }
}

struct NavTab: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Icon(name: icon, size: 36, color: active ? HearthColor.paper : HearthColor.inkSoft)
                Text(label)
                    .font(HearthFont.sans(size: 18, weight: .bold))
                    .foregroundStyle(active ? HearthColor.paper : HearthColor.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(active ? HearthColor.ink : HearthColor.card)
                    .overlay(
                        active
                        ? nil
                        : RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct BottomNav: View {
    @Binding var current: HearthScreen

    var body: some View {
        HStack(spacing: 12) {
            NavTab(icon: "television-simple", label: "Watch",  active: current == .tv)     { current = .tv }
            NavTab(icon: "users-three",       label: "People", active: current == .people) { current = .people }
            NavTab(icon: "sparkle",           label: "Cues",   active: current == .cues)   { current = .cues }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 22)
    }
}

// MARK: - Context strip
// Top-of-screen narration: "Hearth says" + "Heard". The seam the backend will fill.
struct ContextStrip: View {
    let says: String
    let heard: String

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(HearthColor.ember.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .scaleEffect(pulse ? 1.2 : 0.7)
                        .opacity(pulse ? 0 : 0.3)
                    Circle().fill(HearthColor.ember).frame(width: 16, height: 16)
                }
                .padding(.top, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hearth says")
                        .font(HearthFont.sans(size: 13, weight: .bold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(HearthColor.inkMute)
                    Text(says)
                        .font(HearthFont.serif(size: 30, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(HearthColor.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.identity)
                        .animation(nil, value: says)
                        .id(says)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle().fill(HearthColor.border).frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Heard")
                    .font(HearthFont.sans(size: 13, weight: .bold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(HearthColor.inkMute)
                if heard.isEmpty {
                    Text("Listening…")
                        .font(HearthFont.sans(size: 17))
                        .tracking(0.5)
                        .foregroundStyle(HearthColor.inkMute)
                } else {
                    Text("\u{201C}\(heard)\u{201D}")
                        .font(HearthFont.serif(size: 22, weight: .regular).italic())
                        .foregroundStyle(HearthColor.inkSoft)
                        .contentTransition(.identity)
                        .animation(nil, value: heard)
                        .id(heard)
                }
            }
            .padding(.leading, 8)
            .frame(width: 280, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(HearthColor.paperDeep)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Intent chip
struct IntentChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(name: icon, size: 22, color: HearthColor.ember)
                Text(label)
                    .font(HearthFont.sans(size: 22, weight: .bold))
                    .foregroundStyle(HearthColor.ink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(HearthColor.card)
                    .overlay(Capsule().stroke(HearthColor.border, lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page container
struct Page<Content: View>: View {
    var spacing: CGFloat = 20
    var horizontalPadding: CGFloat = 40
    var topPadding: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

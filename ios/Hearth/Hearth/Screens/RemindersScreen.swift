import SwiftUI

struct RemindersScreen: View {
    private let items = RemindersData.today

    var body: some View {
        Page(spacing: 14) {
            ContextStrip(
                says: "You have five things today. One is right now — your medicine.",
                heard: ""
            )
            ForEach(items) { r in
                reminderRow(r)
            }
        }
    }

    private func reminderRow(_ r: ReminderItem) -> some View {
        let tone = palette(for: r.state)
        let isDone = r.state == .done
        return HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(r.time)
                    .font(HearthFont.serif(size: 38, weight: .medium))
                    .tracking(-0.7)
                    .foregroundStyle(tone.text)
                Text(r.ampm)
                    .font(HearthFont.sans(size: 14, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(HearthColor.inkMute)
            }
            .frame(width: 110)

            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(tone.iconBg)
                Icon(name: r.icon, size: 44, color: tone.iconColor)
            }
            .frame(width: 80, height: 80)

            Text(r.title)
                .font(HearthFont.serif(size: 34, weight: .medium))
                .foregroundStyle(tone.text)
                .strikethrough(isDone, color: HearthColor.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)

            if r.state == .now {
                HearthButton("I took it", kind: .confirm, icon: "check") {}
            }
            if isDone {
                Icon(name: "check-circle", size: 36, color: HearthColor.sage)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 24).fill(tone.bg))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(tone.border, lineWidth: 2))
        .opacity(tone.opacity)
        .shadow(color: .black.opacity(r.state == .now ? 0.06 : 0.03),
                radius: r.state == .now ? 8 : 4, x: 0, y: 2)
    }

    private struct ReminderTone {
        let bg: Color
        let border: Color
        let iconBg: Color
        let iconColor: Color
        let text: Color
        let opacity: Double
    }

    private func palette(for state: ReminderItem.State) -> ReminderTone {
        switch state {
        case .done:
            ReminderTone(bg: HearthColor.card, border: HearthColor.borderSoft,
                         iconBg: HearthColor.paperDeep, iconColor: HearthColor.inkMute,
                         text: HearthColor.inkMute, opacity: 0.55)
        case .now:
            ReminderTone(bg: HearthColor.cardWarm, border: HearthColor.honey,
                         iconBg: HearthColor.honey, iconColor: .white,
                         text: HearthColor.ink, opacity: 1)
        case .next:
            ReminderTone(bg: HearthColor.card, border: HearthColor.borderSoft,
                         iconBg: HearthColor.paperDeep, iconColor: HearthColor.inkSoft,
                         text: HearthColor.ink, opacity: 1)
        }
    }
}

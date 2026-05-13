import SwiftUI

struct HomeScreen: View {
    let goTo: (HearthScreen) -> Void
    @Environment(HearthGemma.self) private var gemma
    @State private var calling: FamilyContact? = nil
    @State private var showingSetup = false

    var body: some View {
        Page(spacing: 22) {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                ContextStrip(
                    says: idleLine(now: ctx.date),
                    heard: calling.map { "call my \($0.name == "Sarah" ? "daughter" : "son")" } ?? ""
                )
                .task(id: gemmaTaskKey(now: ctx.date)) {
                    await regenerateIfReady(now: ctx.date)
                }
            }

            nowCard

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Eyebrow(text: "Call someone")
                    Spacer()
                    Text("Just say \u{201C}call my daughter\u{201D} — or tap a face below.")
                        .font(HearthFont.sans(size: 16))
                        .foregroundStyle(HearthColor.inkMute)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                    spacing: 14
                ) {
                    ForEach(FamilyData.all) { p in
                        contactTile(p)
                    }
                }
            }

            companionFooter
        }
        .sheet(isPresented: $showingSetup) {
            GemmaSetupSheet().environment(gemma)
        }
    }

    // MARK: Narration

    // Calling state has its own action-specific line. Otherwise prefer the
    // Gemma-generated line; fall back to a time-aware hardcoded sentence so the
    // screen still reads right when the companion isn't loaded.
    private func idleLine(now: Date) -> String {
        if let c = calling {
            return "Calling \(c.name). You'll see her face when she picks up."
        }
        if let line = gemma.lastHomeLine, !line.isEmpty { return line }
        return fallbackLine(now: now)
    }

    private func fallbackLine(now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning."
        case 12..<17: greeting = "Good afternoon."
        case 17..<22: greeting = "Good evening."
        default:      greeting = "It's late — a quiet hour."
        }
        guard let next = RemindersData.nextReminder(after: now) else { return greeting }
        let item = next.item
        let mins = next.minutesFromNow
        if mins <= 1 {
            return "\(greeting) \(item.title) is right now."
        } else if mins < 60 {
            return "\(greeting) \(item.title) is about \(mins) minutes from now."
        } else {
            return "\(greeting) \(item.title) is at \(item.time) \(item.ampm)."
        }
    }

    // Re-runs whenever this key changes: status flips to ready, or the calendar
    // minute crosses a 5-minute boundary. Keeps inference rare.
    private func gemmaTaskKey(now: Date) -> String {
        let bucket = Int(now.timeIntervalSince1970 / 300)
        let ready = (gemma.status == .ready) ? "1" : "0"
        return "\(ready)-\(bucket)"
    }

    private func regenerateIfReady(now: Date) async {
        guard gemma.status == .ready else { return }
        let next = RemindersData.nextReminder(after: now)
        let nextString: String? = next.map { n in
            let suffix: String
            if n.minutesFromNow <= 1 { suffix = "right now" }
            else if n.minutesFromNow < 60 { suffix = "about \(n.minutesFromNow) minutes away" }
            else { suffix = "at \(n.item.time) \(n.item.ampm)" }
            return "\(n.item.title) (\(suffix))"
        }
        let ctx = HearthGemma.HomeContext(
            timeOfDay: timeOfDay(now: now),
            dayOfWeek: dayOfWeek(now: now),
            clock: clock(now: now),
            nextReminder: nextString
        )
        await gemma.generateHomeLine(ctx)
    }

    private func timeOfDay(now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default:      return "night"
        }
    }
    private func dayOfWeek(now: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: now)
    }
    private func clock(now: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: now)
    }

    // MARK: Now card

    private var nowCard: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(hex: 0xF4E4B8), Color(hex: 0xE8C77B)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Icon(name: "pill", size: 150, color: Color(hex: 0x9C4E2C))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("NOW")
                    .font(HearthFont.sans(size: 14, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(HearthColor.honeyDeep))
                    .padding(18)
            }
            .frame(width: 320)
            .frame(minHeight: 220)

            VStack(alignment: .leading, spacing: 18) {
                Text("Time for your medicine.")
                    .font(HearthFont.serif(size: 46, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(HearthColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    HearthButton("I took it", kind: .confirm, icon: "check") {}
                    HearthButton("Later", kind: .secondary) { goTo(.reminders) }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 32).fill(HearthColor.cardWarm)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32).stroke(HearthColor.honey, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    // MARK: Contacts

    private func contactTile(_ p: FamilyContact) -> some View {
        let isCalling = calling == p
        return Button(action: { calling = p }) {
            VStack(spacing: 10) {
                ZStack {
                    Photo(initial: p.initial, tone: p.tone, size: 130, radius: 22)
                    if isCalling {
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(HearthColor.ember, lineWidth: 3)
                            .frame(width: 142, height: 142)
                    }
                }
                Text(p.name)
                    .font(HearthFont.serif(size: 30, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(HearthColor.ink)
                Text(p.relation)
                    .font(HearthFont.sans(size: 16))
                    .foregroundStyle(HearthColor.inkMute)
                HStack(spacing: 8) {
                    Icon(name: "phone", size: 20, color: isCalling ? .white : HearthColor.sageDeep)
                    Text(isCalling ? "Calling…" : "Call")
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(isCalling ? .white : HearthColor.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(isCalling ? HearthColor.ember : HearthColor.paperDeep))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24).fill(HearthColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isCalling ? HearthColor.ember : HearthColor.borderSoft,
                            lineWidth: isCalling ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Companion footer
    // Discreet entry point — developer-facing. Once the companion is ready,
    // it becomes a quiet status pill instead of a setup CTA.
    private var companionFooter: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { showingSetup = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(companionDotColor)
                        .frame(width: 8, height: 8)
                    Text(companionLabel)
                        .font(HearthFont.sans(size: 14, weight: .bold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(HearthColor.inkMute)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(HearthColor.paperDeep))
                .overlay(Capsule().stroke(HearthColor.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var companionDotColor: Color {
        switch gemma.status {
        case .ready: return HearthColor.sageDeep
        case .downloading, .loadingEngine: return HearthColor.ember
        case .error: return .red
        case .idle: return HearthColor.inkMute
        }
    }

    private var companionLabel: String {
        switch gemma.status {
        case .ready: return "Companion ready"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .loadingEngine: return "Waking companion"
        case .error: return "Companion: error"
        case .idle: return "Set up companion"
        }
    }
}

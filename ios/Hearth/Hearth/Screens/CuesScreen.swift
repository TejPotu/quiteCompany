import SwiftUI
import PhotosUI

// Caregiver-facing indexing UI for the Latent-Intent demo.
// A "Cue" is an entry the caregiver writes once: a list of fuzzy keywords the
// patient says + a sticky-note value Gemma turns into a structured response.
struct CuesScreen: View {
    @Environment(HearthGemma.self) private var gemma
    @Environment(CueStore.self) private var store
    @State private var draft: CueEntry? = nil
    @State private var showingSetup = false

    var body: some View {
        Page(spacing: 24, horizontalPadding: 48, topPadding: 28) {
            ContextStrip(
                says: "Teach Hearth what your loved one says — and what to do.",
                heard: ""
            )

            CompanionStatusCard(status: gemma.status) {
                showingSetup = true
            }

            headerRow

            VStack(spacing: 18) {
                ForEach(store.entries) { entry in
                    CueCard(entry: entry) {
                        draft = entry
                    }
                }
            }
        }
        .sheet(item: $draft) { _ in
            CueEditor(
                entry: $draft,
                isExisting: store.entries.contains(where: { $0.id == draft?.id }),
                onSave: { saved in
                    store.upsert(saved)
                    draft = nil
                },
                onDelete: { id in
                    store.delete(id)
                    draft = nil
                },
                onCancel: { draft = nil }
            )
        }
        .sheet(isPresented: $showingSetup) {
            GemmaSetupSheet()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Eyebrow(text: "Indexed cues")
            Spacer()
            HearthButton("Add cue", kind: .primary, icon: "sparkle") {
                draft = CueEntry.blank
            }
        }
    }
}

// MARK: - Companion status card
// Surfaces Gemma's download/load state inline. Tap opens the full setup sheet
// for actions (download, pause, retry).
private struct CompanionStatusCard: View {
    let status: HearthGemma.Status
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 18) {
                statusDot
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(HearthFont.serif(size: 22, weight: .medium))
                        .foregroundStyle(HearthColor.ink)
                    Text(subtitle)
                        .font(HearthFont.sans(size: 16))
                        .foregroundStyle(HearthColor.inkSoft)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if case .downloading(let p) = status {
                    Text("\(Int(p * 100))%")
                        .font(HearthFont.sans(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(HearthColor.ember)
                }
                Icon(name: "question", size: 22, color: HearthColor.inkMute)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22).fill(HearthColor.card))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(HearthColor.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusDot: some View {
        switch status {
        case .loadingEngine, .downloading:
            ProgressView().controlSize(.regular).tint(HearthColor.ember)
                .frame(width: 28, height: 28)
        case .ready:
            Icon(name: "check-circle", size: 28, color: HearthColor.sageDeep)
        case .error:
            Icon(name: "x-circle", size: 28, color: HearthColor.ember)
        case .idle:
            Circle().fill(HearthColor.inkMute).frame(width: 14, height: 14)
                .padding(7)
        }
    }

    private var title: String {
        switch status {
        case .idle:          return "Voice companion off-line"
        case .downloading:   return "Downloading companion"
        case .loadingEngine: return "Waking the companion"
        case .ready:         return "Voice companion ready"
        case .error:         return "Companion needs attention"
        }
    }

    private var subtitle: String {
        switch status {
        case .idle:                return "Tap to download Gemma 4 — about 2.6 GB, once."
        case .downloading(let p):  return "Keep Hearth open until this finishes (\(Int(p * 100))%)."
        case .loadingEngine:       return "Loading the model into memory — a few seconds."
        case .ready:               return "Cues can now respond with grounded, warm replies."
        case .error(let msg):      return msg
        }
    }
}

// MARK: - Store
// Lifted out of CuesScreen so the Watch tab's voice orchestrator can read the
// same set the caregiver authored on Cues. In-memory only for now.
@Observable @MainActor
final class CueStore {
    var entries: [CueEntry]

    init(initial: [CueEntry] = CueEntry.demoSeed) {
        self.entries = initial
    }

    func upsert(_ entry: CueEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    // Case-insensitive lookup. Used by the voice orchestrator to grab the
    // caregiver's verbatim value after Gemma matches a cue.
    func find(byName name: String) -> CueEntry? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        return entries.first { $0.name.lowercased() == needle }
            ?? entries.first { $0.name.lowercased().contains(needle) }
    }
}

// MARK: - Model

struct CueEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var keywords: [String]
    var value: String
    var imageName: String?       // optional Phosphor name fallback (e.g. "pill")
    var imageData: Data?         // caregiver-uploaded photo bytes
    var schedule: String?        // e.g. "09:00 daily (±30 min)"
    var threshold: String?       // e.g. "≥80°F hot / 60–79°F moderate / ≤50°F cold"
    var expiresAt: Date?         // nil = never expires (caregiver-authored cues);
                                 // set for inbound family notes so yesterday's
                                 // "home by 8" doesn't poison today's answers

    /// Whether this cue is still in effect right now. Caregiver cues with
    /// no expiry are always live; family notes drop out 24h after sending.
    var isLive: Bool {
        guard let expiresAt else { return true }
        return Date() < expiresAt
    }

    static let blank = CueEntry(
        name: "",
        keywords: [],
        value: "",
        imageName: nil,
        imageData: nil,
        schedule: nil,
        threshold: nil,
        expiresAt: nil
    )

    static let demoSeed: [CueEntry] = [
        CueEntry(
            name: "Medicine",
            keywords: [
                "is it time for my medicine?",
                "did I take my pills?",
                "where are my pills?",
                "tablets"
            ],
            value: "Take meds at 9 AM. Pill organizer is on the desk near the TV. Take the red pill from the morning slot.",
            imageName: "pill",
            schedule: "09:00 daily (±30 min)",
            threshold: nil
        ),
        CueEntry(
            name: "Weather",
            keywords: [
                "what's the weather?",
                "is it cold?",
                "should I take a jacket?"
            ],
            value: "Tell him how it feels — hot, moderate, or cold — not just the number.",
            imageName: nil,
            schedule: nil,
            threshold: "≥80°F hot · 60–79°F moderate · ≤50°F cold"
        ),
        CueEntry(
            name: "Favorite show",
            keywords: [
                "what time is it?",
                "what's on?",
                "is it time yet?"
            ],
            value: "Evening news airs at 5:30 PM on Channel 5. Inside the window, ask if he wants it on. Outside the window, just say the time.",
            imageName: nil,
            schedule: "17:30 daily (±5 min)",
            threshold: nil
        )
    ]
}

// MARK: - Card

private struct CueCard: View {
    let entry: CueEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 18) {
                cueThumbnail
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.name.isEmpty ? "Untitled cue" : entry.name)
                            .font(HearthFont.serif(size: 36, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(HearthColor.ink)
                        Spacer()
                        if let s = entry.schedule {
                            pillTag(text: s, color: HearthColor.ember)
                        }
                        if let t = entry.threshold {
                            pillTag(text: t, color: HearthColor.sageDeep)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("HEARS")
                            .font(HearthFont.sans(size: 14, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HearthColor.inkMute)
                        FlowLayout(spacing: 8) {
                            ForEach(entry.keywords, id: \.self) { kw in
                                Text("\u{201C}\(kw)\u{201D}")
                                    .font(HearthFont.sans(size: 17))
                                    .foregroundStyle(HearthColor.inkSoft)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(HearthColor.cardWarm)
                                    )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("RESPONDS WITH")
                            .font(HearthFont.sans(size: 14, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HearthColor.inkMute)
                        Text(entry.value)
                            .font(HearthFont.serif(size: 20, weight: .medium))
                            .foregroundStyle(HearthColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28).fill(HearthColor.card))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(HearthColor.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var cueThumbnail: some View {
        if let data = entry.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(HearthColor.borderSoft, lineWidth: 1))
        } else if let name = entry.imageName, !name.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(HearthColor.cardWarm)
                Icon(name: name, size: 48, color: HearthColor.ember)
            }
            .frame(width: 96, height: 96)
        }
    }

    private func pillTag(text: String, color: Color) -> some View {
        Text(text)
            .font(HearthFont.sans(size: 14, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Editor (sheet for adding/editing a cue)

private struct CueEditor: View {
    @Binding var entry: CueEntry?
    let isExisting: Bool
    let onSave: (CueEntry) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var keywordsRaw: String = ""
    @State private var value: String = ""
    @State private var schedule: String = ""
    @State private var threshold: String = ""
    @State private var imageData: Data? = nil
    @State private var imageName: String? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(isExisting ? "Edit cue" : "New cue")
                    .font(HearthFont.serif(size: 36, weight: .medium))
                    .foregroundStyle(HearthColor.ink)

                imageRow

                field("ENTRY NAME") {
                    TextField("Medicine", text: $name)
                        .font(HearthFont.sans(size: 20))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                field("KEYWORDS (one per line)") {
                    TextEditor(text: $keywordsRaw)
                        .font(HearthFont.sans(size: 18))
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                field("VALUE — write it like a sticky note") {
                    TextEditor(text: $value)
                        .font(HearthFont.serif(size: 19))
                        .frame(minHeight: 130)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                HStack(spacing: 18) {
                    field("SCHEDULE (optional)") {
                        TextField("09:00 daily", text: $schedule)
                            .font(HearthFont.sans(size: 18))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                    }
                    field("THRESHOLD (optional)") {
                        TextField("\u{2265}80\u{00B0}F hot \u{00B7} \u{2264}50\u{00B0}F cold", text: $threshold)
                            .font(HearthFont.sans(size: 18))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                    }
                }

                actionRow
            }
            .padding(36)
        }
        .background(HearthColor.paper.ignoresSafeArea())
        .onAppear {
            guard let e = entry else { return }
            name = e.name
            keywordsRaw = e.keywords.joined(separator: "\n")
            value = e.value
            schedule = e.schedule ?? ""
            threshold = e.threshold ?? ""
            imageData = e.imageData
            imageName = e.imageName
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    imageData = data
                    imageName = nil
                }
            }
        }
        .confirmationDialog(
            "Delete this cue?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = entry?.id { onDelete(id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hearth will forget this cue. This cannot be undone.")
        }
    }

    private var imageRow: some View {
        HStack(spacing: 18) {
            imagePreview
            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack(spacing: 10) {
                        Icon(name: "sparkle", size: 22, color: .white)
                        Text(imageData == nil && imageName == nil ? "Add image" : "Replace image")
                            .font(HearthFont.sans(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(HearthColor.ember))
                }
                .buttonStyle(.plain)

                if imageData != nil || imageName != nil {
                    Button {
                        imageData = nil
                        imageName = nil
                        pickerItem = nil
                    } label: {
                        Text("Remove image")
                            .font(HearthFont.sans(size: 16, weight: .bold))
                            .foregroundStyle(HearthColor.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var imagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(HearthColor.cardWarm)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(HearthColor.borderSoft, lineWidth: 1))
            if let data = imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else if let name = imageName, !name.isEmpty {
                Icon(name: name, size: 56, color: HearthColor.ember)
            } else {
                Icon(name: "sparkle", size: 40, color: HearthColor.inkMute)
            }
        }
        .frame(width: 120, height: 120)
    }

    private var actionRow: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(HearthFont.sans(size: 18, weight: .bold))
                .foregroundStyle(HearthColor.inkSoft)
            if isExisting {
                Button {
                    confirmingDelete = true
                } label: {
                    Text("Delete")
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(.red)
                }
                .padding(.leading, 20)
            }
            Spacer()
            HearthButton("Save cue", kind: .primary, icon: "check") {
                var saved = entry ?? CueEntry.blank
                saved.name = name
                saved.keywords = keywordsRaw
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                saved.value = value
                saved.schedule = schedule.isEmpty ? nil : schedule
                saved.threshold = threshold.isEmpty ? nil : threshold
                saved.imageData = imageData
                saved.imageName = imageName
                onSave(saved)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(HearthFont.sans(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(HearthColor.inkMute)
            content()
        }
    }
}

// MARK: - Flow layout for keyword chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

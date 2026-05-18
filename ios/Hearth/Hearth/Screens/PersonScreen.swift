import SwiftUI
import UIKit
import PhotosUI

// People tab — two audiences, one screen.
//
//   Patient flow: tab opens → camera auto-launches → snap → on-device face
//   matcher checks against indexed people → reveal a big "This is X" card
//   with the caregiver-authored notes. If no match, gentle "I don't
//   recognise them yet" card with a retry button.
//
//   Caregiver flow: cancel the camera (or use the "Index someone" button)
//   to reach the indexing list. Standard CRUD — name, relationship, photo,
//   short note. Photo can come from the camera or the photo library; either
//   way we compute and cache a face fingerprint at save time so matches at
//   query time are just distance comparisons.
struct PersonScreen: View {
    @Environment(PeopleStore.self) private var store
    @Environment(HearthGemma.self) private var gemma
    @Environment(HearthTTS.self) private var tts

    @State private var capturedImage: UIImage? = nil
    @State private var matchResult: MatchOutcome? = nil
    @State private var showingCamera = false
    @State private var hasAutoOpenedCamera = false
    @State private var draft: PersonEntry? = nil
    @State private var matching = false
    @State private var matchStage: MatchStage = .idle
    @State private var matcherUsed: MatcherSource? = nil
    @State private var verifyLog: [VerifyLogEntry] = []
    @State private var showingRoster = false

    struct VerifyLogEntry: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let isMatch: Bool
        let reasoning: String
    }

    enum MatchOutcome: Equatable {
        case found(PersonEntry)
        case unknown
    }

    enum MatchStage: Equatable {
        case idle
        case retrieving                       // running Apple FeaturePrint
        case verifying(name: String, rank: Int, total: Int)  // current Gemma check
    }

    enum MatcherSource: String {
        case visionOnly        // Gemma not loaded; Apple top-1 alone
        case confirmedByGemma  // Gemma said yes to Apple's top-1
        case rerankedByGemma   // Gemma swapped to a later candidate
    }

    var body: some View {
        Page(spacing: 24, horizontalPadding: 48, topPadding: 28) {
            ContextStrip(
                says: hearthSays,
                heard: ""
            )

            captureResultCard
                .animation(.easeInOut(duration: 0.25), value: matchStateKey)
                .onChange(of: matchStateKey) { _, _ in
                    if !matching { speakResult(matchResult) }
                }

            manageRosterPill
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureSheet(
                preferFrontCamera: false,
                onCapture: { image in
                    showingCamera = false
                    Task { await runMatch(on: image) }
                },
                onCancel: {
                    showingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $draft) { _ in
            PersonEditor(
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
        .sheet(isPresented: $showingRoster) {
            RosterSheet(
                entries: store.entries,
                onAdd: {
                    showingRoster = false
                    draft = PersonEntry.blank
                },
                onEdit: { entry in
                    showingRoster = false
                    draft = entry
                },
                onDelete: { id in store.delete(id) },
                onDismiss: { showingRoster = false }
            )
        }
        .task {
            // Auto-open camera the first time we land on this tab in a
            // session, but only if there's at least one indexed person to
            // match against. Otherwise the caregiver clearly needs to
            // index someone first.
            if !hasAutoOpenedCamera, !store.entries.isEmpty {
                hasAutoOpenedCamera = true
                showingCamera = true
            }
        }
    }

    private var hearthSays: String {
        switch matchResult {
        case .found(let p):
            let rel = p.relationship.isEmpty ? "" : ", \(p.relationship.lowercased())"
            return "This is \(p.name)\(rel)."
        case .unknown:
            return "I don't recognise them yet. Ask Sarah to add them."
        case .none:
            if !matching {
                return "Hold the camera up to a face and I'll tell you who it is."
            }
            switch matchStage {
            case .retrieving:
                return "Looking for similar faces…"
            case .verifying(let name, let rank, let total):
                return "Asking Gemma to confirm \(name) (\(rank)/\(total))…"
            case .idle:
                return "Looking…"
            }
        }
    }

    // MARK: - Match flow
    //
    // Apple Vision drives the decision; Gemma can refine it.
    //
    //   1) RETRIEVE — FeaturePrint ranks indexed people by face-print
    //      distance and returns the top 3. Apple's top-1 is the default
    //      answer (the pure-Apple path worked on its own, so we trust it
    //      when there's nothing better).
    //   2) RERANK — if Gemma is loaded, walk the top-3 in rank order and
    //      ask the pairwise "same person?" question. The FIRST yes wins,
    //      which means Gemma can SWAP the answer from top-1 to top-2 or
    //      top-3 when its judgement disagrees. But if Gemma rejects all
    //      three, we keep Apple's top-1 — Gemma is a re-ranker, not a
    //      veto.
    //   3) UNKNOWN — only when no face/featureprint at all, or even
    //      Apple's closest is too far away to be plausible.
    private func runMatch(on image: UIImage) async {
        capturedImage = image
        matching = true
        matchStage = .idle
        matcherUsed = nil
        verifyLog = []
        defer {
            matching = false
            matchStage = .idle
        }

        guard let capturedJpeg = image.jpegData(compressionQuality: 0.85) else {
            matchResult = .unknown
            return
        }

        // Stage 1 — Apple FeaturePrint top-3.
        matchStage = .retrieving
        let shortlist = await FaceMatcher.topCandidates(
            captured: image,
            against: store.entries,
            k: 3
        )

        guard let bestApple = shortlist.first else {
            matchResult = .unknown
            return
        }

        // Distance above this is "probably not in the roster at all" — stay
        // honest rather than parading a wildly wrong top-1. FeaturePrint
        // distances on random unrelated faces sit comfortably above 25.
        let unknownDistanceThreshold: Float = 25.0
        guard bestApple.distance <= unknownDistanceThreshold else {
            matchResult = .unknown
            return
        }

        // Stage 2 — Gemma re-ranks within the top-3 if it's loaded.
        //
        // When Gemma is loaded, Gemma's verdict is authoritative — it has
        // the only real understanding of identity. If it says yes to any
        // candidate, that wins. If it says no to all three, we surface
        // unknown rather than parading a wrong Apple top-1 with three ✗
        // rejections underneath it (which would be both confusing and
        // dishonest).
        //
        // When Gemma is NOT loaded, we fall back to Apple's top-1 since
        // that's the best signal we have.
        if case .ready = gemma.status {
            var gemmaPick: (entry: PersonEntry, source: MatcherSource)? = nil
            for (idx, candidate) in shortlist.enumerated() {
                matchStage = .verifying(
                    name: candidate.entry.name,
                    rank: idx + 1,
                    total: shortlist.count
                )
                guard let reference = candidate.entry.photoData else { continue }
                let result = await gemma.verifySamePerson(
                    capturedJpeg: capturedJpeg,
                    referenceJpeg: reference
                )
                verifyLog.append(VerifyLogEntry(
                    name: candidate.entry.name,
                    isMatch: result.isMatch,
                    reasoning: result.reasoning
                ))
                if result.isMatch {
                    gemmaPick = (candidate.entry, idx == 0 ? .confirmedByGemma : .rerankedByGemma)
                    break
                }
            }
            if let pick = gemmaPick {
                matcherUsed = pick.source
                matchResult = .found(pick.entry)
            } else {
                matcherUsed = nil
                matchResult = .unknown  // Gemma rejected everyone — stay honest
            }
        } else {
            matcherUsed = .visionOnly
            matchResult = .found(bestApple.entry)
        }
    }

    // Read the match result aloud once matching finishes. Hooked from
    // .onChange of matchStateKey so it fires on every settled state, not
    // just the first one in a session.
    private func speakResult(_ result: MatchOutcome?) {
        switch result {
        case .found(let entry):
            let rel = entry.relationship.isEmpty ? "" : ", \(entry.relationship.lowercased())"
            var line = "This is \(entry.name)\(rel)."
            if let notes = entry.notes, !notes.isEmpty {
                line += " " + notes
            }
            tts.speak(line)
        case .unknown:
            tts.speak("I don't recognise them. Ask Sarah to add them.")
        case .none:
            break
        }
    }

    // MARK: - Result card

    @ViewBuilder private var captureResultCard: some View {
        // Matching dominates the screen while it's running so the user
        // sees the pipeline working in real time — no stale prior result
        // peeking through.
        if matching {
            MatchingInFlightCard(
                capturedImage: capturedImage,
                stage: matchStage,
                verifyLog: verifyLog
            )
            .transition(.opacity)
        } else {
            switch matchResult {
            case .found(let entry):
                MatchedPersonCard(
                    entry: entry,
                    capturedImage: capturedImage,
                    matcher: matcherUsed,
                    verifyLog: verifyLog,
                    onAgain: { showingCamera = true }
                )
                .transition(.opacity)
            case .unknown:
                UnknownPersonCard(
                    capturedImage: capturedImage,
                    verifyLog: verifyLog,
                    onAgain: { showingCamera = true },
                    onIndex: {
                        // Pre-fill the editor with the just-captured photo so
                        // Sarah can name them in one tap.
                        var entry = PersonEntry.blank
                        if let img = capturedImage, let data = img.jpegData(compressionQuality: 0.85) {
                            entry.photoData = data
                        }
                        draft = entry
                    }
                )
                .transition(.opacity)
            case .none:
                CameraPromptCard(
                    hasIndexed: !store.entries.isEmpty,
                    onOpen: { showingCamera = true }
                )
                .transition(.opacity)
            }
        }
    }

    // Animation hook: changes whenever the high-level visible state of the
    // result area changes. Used by `.animation(_:value:)` to fade between
    // matching → result transitions smoothly.
    private var matchStateKey: String {
        if matching { return "matching" }
        switch matchResult {
        case .found(let e): return "found-\(e.id.uuidString)"
        case .unknown:      return "unknown"
        case .none:         return "idle"
        }
    }

    // Caregiver entry point — a single, low-weight pill that opens the
    // full roster as a sheet. Sits at the bottom of the page so it's
    // accessible but not visually loud during normal patient use.
    private var manageRosterPill: some View {
        HStack {
            Spacer()
            Button {
                showingRoster = true
            } label: {
                HStack(spacing: 12) {
                    Icon(name: "users-three", size: 20, color: HearthColor.ember)
                    Text(rosterPillLabel)
                        .font(HearthFont.sans(size: 17, weight: .bold))
                        .foregroundStyle(HearthColor.ink)
                    Icon(name: "pencil", size: 14, color: HearthColor.inkMute)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Capsule().fill(HearthColor.card))
                .overlay(Capsule().stroke(HearthColor.borderSoft, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 12)
    }

    private var rosterPillLabel: String {
        let count = store.entries.count
        if count == 0 { return "Index someone" }
        return "Manage roster · \(count)"
    }

}

// MARK: - Shared reasoning trail
//
// The same Gemma-trace block appears under the in-flight, matched, and
// unknown cards. Extracted so the visual treatment stays identical across
// all three states.
private struct ReasoningTrail: View {
    let entries: [PersonScreen.VerifyLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            trailBox
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Icon(name: "sparkle", size: 16, color: HearthColor.ember)
            Text("GEMMA REASONED")
                .font(HearthFont.sans(size: 13, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(HearthColor.ember)
            Rectangle()
                .fill(HearthColor.ember.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var trailBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 14) {
                    Icon(
                        name: entry.isMatch ? "check-circle" : "x-circle",
                        size: 20,
                        color: entry.isMatch ? HearthColor.sageDeep : HearthColor.inkMute
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name)
                            .font(HearthFont.sans(size: 16, weight: .bold))
                            .foregroundStyle(HearthColor.ink)
                        Text(entry.reasoning)
                            .font(HearthFont.serif(size: 17).italic())
                            .foregroundStyle(HearthColor.inkSoft)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HearthColor.borderSoft, lineWidth: 1))
    }
}

// MARK: - In-flight card
//
// Visible only while a match is running. Surfaces three things in one
// glance so the user sees Gemma working in real time:
//   1) the just-captured snapshot,
//   2) what the matcher is doing right now (retrieve / which candidate
//      Gemma is verifying),
//   3) the running tally of verdicts Gemma has already returned for this
//      run — each row animates in as it lands.
private struct MatchingInFlightCard: View {
    let capturedImage: UIImage?
    let stage: PersonScreen.MatchStage
    let verifyLog: [PersonScreen.VerifyLogEntry]

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 32) {
                snapshotView
                statusBlock
                Spacer(minLength: 0)
            }
            if !verifyLog.isEmpty {
                Divider().background(HearthColor.borderSoft)
                ReasoningTrail(entries: verifyLog)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(HearthColor.ember.opacity(0.4), lineWidth: 2))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .animation(.easeInOut(duration: 0.3), value: verifyLog.count)
    }

    @ViewBuilder private var snapshotView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(HearthColor.cardWarm)
            if let captured = capturedImage {
                Image(uiImage: captured)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                Icon(name: "camera", size: 56, color: HearthColor.inkMute)
            }
            // Subtle "scan" overlay so the snapshot feels actively examined.
            RoundedRectangle(cornerRadius: 24)
                .stroke(HearthColor.ember.opacity(pulse ? 0.55 : 0.15), lineWidth: 3)
        }
        .frame(width: 180, height: 180)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(HearthColor.ember.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .scaleEffect(pulse ? 1.3 : 0.8)
                        .opacity(pulse ? 0 : 0.5)
                    Circle().fill(HearthColor.ember).frame(width: 14, height: 14)
                }
                Text(headline)
                    .font(HearthFont.sans(size: 14, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(HearthColor.ember)
            }
            Text(statusText)
                .font(HearthFont.serif(size: 30, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(HearthColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if case let .verifying(_, rank, total) = stage {
                ProgressView(value: Double(rank), total: Double(total))
                    .tint(HearthColor.ember)
                    .frame(maxWidth: 320)
            }
        }
    }

    private var headline: String {
        switch stage {
        case .retrieving:                   return "STAGE 1 / 2 — APPLE VISION"
        case .verifying(_, let rank, let total): return "STAGE 2 / 2 — GEMMA · \(rank) OF \(total)"
        case .idle:                          return "WORKING"
        }
    }

    private var statusText: String {
        switch stage {
        case .retrieving:
            return "Looking for the closest faces in the roster…"
        case .verifying(let name, _, _):
            return "Asking Gemma if this is \(name)…"
        case .idle:
            return "Thinking…"
        }
    }

}

// MARK: - Result cards

private struct MatchedPersonCard: View {
    let entry: PersonEntry
    let capturedImage: UIImage?
    let matcher: PersonScreen.MatcherSource?
    let verifyLog: [PersonScreen.VerifyLogEntry]
    let onAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            personRow
            if !verifyLog.isEmpty {
                Divider().background(HearthColor.borderSoft)
                ReasoningTrail(entries: verifyLog)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(HearthColor.ember, lineWidth: 3))
    }

    private var personRow: some View {
        HStack(alignment: .top, spacing: 32) {
            PortraitView(data: entry.photoData, fallback: entry.name)
                .frame(width: 200, height: 200)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("THIS IS")
                        .font(HearthFont.sans(size: 16, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(HearthColor.inkMute)
                    matcherChip
                }
                Text(entry.name)
                    .font(HearthFont.serif(size: 72, weight: .medium))
                    .tracking(-1.2)
                    .foregroundStyle(HearthColor.ink)
                if !entry.relationship.isEmpty {
                    Text(entry.relationship)
                        .font(HearthFont.serif(size: 30, weight: .medium))
                        .foregroundStyle(HearthColor.emberDeep)
                        .padding(.top, 4)
                }

                HStack(spacing: 18) {
                    if let from = entry.from, !from.isEmpty {
                        Label {
                            Text("From \(from)")
                                .font(HearthFont.sans(size: 20, weight: .bold))
                                .foregroundStyle(HearthColor.inkSoft)
                        } icon: {
                            Icon(name: "map-pin", size: 20, color: HearthColor.ember)
                        }
                    }
                    if let birthday = entry.birthday {
                        Label {
                            Text(birthday, format: .dateTime.month(.abbreviated).day())
                                .font(HearthFont.sans(size: 20, weight: .bold))
                                .foregroundStyle(HearthColor.inkSoft)
                        } icon: {
                            Icon(name: "cake", size: 20, color: HearthColor.ember)
                        }
                    }
                }
                .padding(.top, 12)

                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(HearthFont.serif(size: 20))
                        .foregroundStyle(HearthColor.inkSoft)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 14) {
                if let captured = capturedImage {
                    VStack(spacing: 8) {
                        Image(uiImage: captured)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HearthColor.borderSoft, lineWidth: 1))
                        Text("JUST SNAPPED")
                            .font(HearthFont.sans(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HearthColor.inkMute)
                    }
                }
                HearthButton("Look again", kind: .secondary, icon: "camera", action: onAgain)
            }
            .frame(width: 160)
        }
    }

    @ViewBuilder private var matcherChip: some View {
        let (label, color): (String, Color) = {
            switch matcher {
            case .confirmedByGemma:
                return ("Confirmed by Gemma", HearthColor.ember)
            case .rerankedByGemma:
                return ("Re-ranked by Gemma", HearthColor.ember)
            case .visionOnly:
                return ("Recognised by Vision", HearthColor.sageDeep)
            case .none:
                return ("", .clear)
            }
        }()
        if !label.isEmpty {
            Text(label)
                .font(HearthFont.sans(size: 12, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
        }
    }
}

private struct UnknownPersonCard: View {
    let capturedImage: UIImage?
    let verifyLog: [PersonScreen.VerifyLogEntry]
    let onAgain: () -> Void
    let onIndex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 32) {
                if let captured = capturedImage {
                    Image(uiImage: captured)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(HearthColor.borderSoft, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("I don't recognise them")
                        .font(HearthFont.serif(size: 36, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(HearthColor.ink)
                    Text(subtitle)
                        .font(HearthFont.sans(size: 18))
                        .foregroundStyle(HearthColor.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        HearthButton("Look again", kind: .secondary, icon: "camera", action: onAgain)
                        HearthButton("Add this person", kind: .primary, icon: "plus", action: onIndex)
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
            if !verifyLog.isEmpty {
                Divider().background(HearthColor.borderSoft)
                ReasoningTrail(entries: verifyLog)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    private var subtitle: String {
        verifyLog.isEmpty
            ? "Ask Sarah to add this person, or try the photo again."
            : "Gemma checked the closest matches and didn't see this person among them."
    }

}

private struct CameraPromptCard: View {
    let hasIndexed: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(HearthColor.cardWarm)
                Icon(name: "camera", size: 64, color: HearthColor.ember)
            }
            .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 12) {
                Text(hasIndexed ? "Who is this?" : "Index someone to begin")
                    .font(HearthFont.serif(size: 36, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(HearthColor.ink)
                Text(hasIndexed
                     ? "Point the camera at a face and I'll tell you their name."
                     : "Add a few people first so Hearth has something to compare against.")
                    .font(HearthFont.sans(size: 18))
                    .foregroundStyle(HearthColor.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if hasIndexed {
                    HearthButton("Open camera", kind: .primary, icon: "camera", action: onOpen)
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(HearthColor.borderSoft, lineWidth: 1))
    }
}

// MARK: - Index list row

private struct PersonRow: View {
    let entry: PersonEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 18) {
                PortraitView(data: entry.photoData, fallback: entry.name)
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name.isEmpty ? "Untitled person" : entry.name)
                        .font(HearthFont.serif(size: 28, weight: .medium))
                        .foregroundStyle(HearthColor.ink)
                    if !entry.relationship.isEmpty {
                        Text(entry.relationship)
                            .font(HearthFont.sans(size: 18, weight: .bold))
                            .foregroundStyle(HearthColor.emberDeep)
                    }
                    HStack(spacing: 14) {
                        if let from = entry.from, !from.isEmpty {
                            Text(from)
                                .font(HearthFont.sans(size: 15))
                                .foregroundStyle(HearthColor.inkSoft)
                        }
                        if entry.featurePrintData == nil {
                            Text("No fingerprint")
                                .font(HearthFont.sans(size: 13, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().stroke(.orange.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                Spacer()
                Icon(name: "pencil", size: 22, color: HearthColor.inkMute)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.card))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Portrait helper

private struct PortraitView: View {
    let data: Data?
    let fallback: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(PhotoTone.ember.gradient)
            if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                Text(String(fallback.prefix(1)).uppercased())
                    .font(HearthFont.serif(size: 64, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(HearthColor.borderSoft, lineWidth: 1))
    }
}

// MARK: - Editor

private struct PersonEditor: View {
    @Binding var entry: PersonEntry?
    let isExisting: Bool
    let onSave: (PersonEntry) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var relationship: String = ""
    @State private var from: String = ""
    @State private var notes: String = ""
    @State private var birthday: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var photoData: Data? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    @State private var confirmingDelete = false
    @State private var computingFingerprint = false
    @State private var fingerprintWarning: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(isExisting ? "Edit person" : "Index someone")
                    .font(HearthFont.serif(size: 36, weight: .medium))
                    .foregroundStyle(HearthColor.ink)

                photoRow

                field("NAME") {
                    TextField("Sarah", text: $name)
                        .font(HearthFont.sans(size: 20))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                field("RELATIONSHIP") {
                    TextField("Your daughter", text: $relationship)
                        .font(HearthFont.sans(size: 20))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                HStack(spacing: 18) {
                    field("FROM (optional)") {
                        TextField("Brighton", text: $from)
                            .font(HearthFont.sans(size: 18))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                    }
                    field("BIRTHDAY (optional)") {
                        Toggle(isOn: $hasBirthday) {
                            Text(hasBirthday ? "Pick a day" : "No birthday")
                                .font(HearthFont.sans(size: 15))
                                .foregroundStyle(HearthColor.inkSoft)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                        if hasBirthday {
                            DatePicker("", selection: $birthday, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }

                field("NOTES (what should Hearth remind them about?)") {
                    TextEditor(text: $notes)
                        .font(HearthFont.serif(size: 19))
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                }

                if let warning = fingerprintWarning {
                    HStack(spacing: 10) {
                        Icon(name: "x-circle", size: 18, color: .orange)
                        Text(warning)
                            .font(HearthFont.sans(size: 15))
                            .foregroundStyle(HearthColor.inkSoft)
                    }
                }

                actionRow
            }
            .padding(36)
        }
        .background(HearthColor.paper.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureSheet(
                preferFrontCamera: true,
                onCapture: { image in
                    showingCamera = false
                    photoData = image.jpegData(compressionQuality: 0.85)
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard let e = entry else { return }
            name = e.name
            relationship = e.relationship
            from = e.from ?? ""
            notes = e.notes ?? ""
            if let b = e.birthday {
                birthday = b
                hasBirthday = true
            }
            photoData = e.photoData
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
        .confirmationDialog(
            "Forget this person?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = entry?.id { onDelete(id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hearth will no longer recognise them.")
        }
    }

    private var photoRow: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(HearthColor.cardWarm)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(HearthColor.borderSoft, lineWidth: 1))
                if let data = photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                } else {
                    Icon(name: "user", size: 64, color: HearthColor.inkMute)
                }
            }
            .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 12) {
                HearthButton("Take photo", kind: .primary, icon: "camera") {
                    showingCamera = true
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack(spacing: 10) {
                        Icon(name: "sparkle", size: 20, color: HearthColor.ink)
                        Text("Choose from photos")
                            .font(HearthFont.sans(size: 18, weight: .bold))
                            .foregroundStyle(HearthColor.ink)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(HearthColor.paperDeep))
                }
                .buttonStyle(.plain)
                if photoData != nil {
                    Button {
                        photoData = nil
                        pickerItem = nil
                        fingerprintWarning = nil
                    } label: {
                        Text("Remove photo")
                            .font(HearthFont.sans(size: 16, weight: .bold))
                            .foregroundStyle(HearthColor.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
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
            if computingFingerprint {
                ProgressView().controlSize(.regular).tint(HearthColor.ember)
                    .padding(.trailing, 8)
            }
            HearthButton("Save person", kind: .primary, icon: "check") {
                Task { await save() }
            }
            .disabled(computingFingerprint)
        }
    }

    private func save() async {
        var saved = entry ?? PersonEntry.blank
        saved.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.from = from.isEmpty ? nil : from
        saved.notes = notes.isEmpty ? nil : notes
        saved.birthday = hasBirthday ? birthday : nil
        saved.photoData = photoData

        // Recompute the FeaturePrint when the photo changes — that's what
        // the retrieval stage uses to shortlist this person. Gemma is not
        // touched at index time; it runs at query time over the shortlist.
        if let data = photoData, let img = UIImage(data: data) {
            let needsRecompute = (entry?.photoData != photoData) || saved.featurePrintData == nil
            if needsRecompute {
                computingFingerprint = true
                defer { computingFingerprint = false }
                if let fp = await FaceMatcher.computeFingerprint(for: img) {
                    saved.featurePrintData = fp
                    fingerprintWarning = nil
                } else {
                    saved.featurePrintData = nil
                    fingerprintWarning = "I couldn't find a clear face in that photo. Try one with the face larger and well lit."
                    return
                }
            }
        } else {
            saved.featurePrintData = nil
        }
        onSave(saved)
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

// MARK: - Roster sheet (caregiver-only)
//
// Lives in a modal sheet so it never clutters the patient-facing view.
// Tapping a row hands the entry back to PersonScreen, which closes the
// sheet and opens the existing PersonEditor. Swipe-delete on each row.
private struct RosterSheet: View {
    let entries: [PersonEntry]
    let onAdd: () -> Void
    let onEdit: (PersonEntry) -> Void
    let onDelete: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var confirmingDelete: PersonEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(HearthColor.borderSoft)
            ScrollView {
                if entries.isEmpty {
                    emptyState
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(entries) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .background(HearthColor.paper.ignoresSafeArea())
        .confirmationDialog(
            "Forget \(confirmingDelete?.name ?? "this person")?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { person in
            Button("Delete", role: .destructive) {
                onDelete(person.id)
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: { _ in
            Text("Hearth will no longer recognise them.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Icon(name: "users-three", size: 28, color: HearthColor.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text("Indexed people")
                    .font(HearthFont.serif(size: 28, weight: .medium))
                    .foregroundStyle(HearthColor.ink)
                Text("\(entries.count) \(entries.count == 1 ? "person" : "people") Hearth knows")
                    .font(HearthFont.sans(size: 14))
                    .foregroundStyle(HearthColor.inkSoft)
            }
            Spacer()
            HearthButton("Add", kind: .primary, icon: "plus", action: onAdd)
            Button(action: onDismiss) {
                Icon(name: "x-circle", size: 28, color: HearthColor.inkMute)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Icon(name: "user", size: 56, color: HearthColor.inkMute)
            Text("No one indexed yet")
                .font(HearthFont.serif(size: 26, weight: .medium))
                .foregroundStyle(HearthColor.ink)
            Text("Add a face Hearth should recognise — a relative, a friend, a neighbour.")
                .font(HearthFont.sans(size: 17))
                .foregroundStyle(HearthColor.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HearthButton("Index someone", kind: .primary, icon: "plus", action: onAdd)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(for entry: PersonEntry) -> some View {
        HStack(spacing: 18) {
            Button {
                onEdit(entry)
            } label: {
                HStack(spacing: 18) {
                    PortraitView(data: entry.photoData, fallback: entry.name)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name.isEmpty ? "Untitled person" : entry.name)
                            .font(HearthFont.serif(size: 22, weight: .medium))
                            .foregroundStyle(HearthColor.ink)
                        if !entry.relationship.isEmpty {
                            Text(entry.relationship)
                                .font(HearthFont.sans(size: 15, weight: .bold))
                                .foregroundStyle(HearthColor.emberDeep)
                        }
                        HStack(spacing: 10) {
                            if let from = entry.from, !from.isEmpty {
                                Text(from)
                                    .font(HearthFont.sans(size: 13))
                                    .foregroundStyle(HearthColor.inkSoft)
                            }
                            if entry.featurePrintData == nil {
                                Text("No fingerprint")
                                    .font(HearthFont.sans(size: 11, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().stroke(.orange.opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Icon(name: "pencil", size: 18, color: HearthColor.inkMute)
                }
            }
            .buttonStyle(.plain)

            Button {
                confirmingDelete = entry
            } label: {
                Icon(name: "trash", size: 18, color: .red.opacity(0.8))
                    .padding(10)
                    .background(Circle().fill(Color.red.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HearthColor.borderSoft, lineWidth: 1))
    }
}

import SwiftUI
import Combine

struct TVScreen: View {
    @Environment(RokuController.self) private var roku
    @Environment(HearthGemma.self) private var gemma
    @Environment(CueStore.self) private var cues
    @Environment(PresenceMonitor.self) private var presence
    @Environment(CaregiverAlerter.self) private var alerter
    @State private var showingWellness = false
    @State private var ingestedInboxIds: Set<Int> = []
    @State private var paused = false
    @State private var stopped = false
    @State private var playing: Show = FavouritesData.all[0]
    @State private var says: String = "Now playing \(FavouritesData.all[0].title). \(FavouritesData.all[0].episode). You're \(FavouritesData.all[0].resume)."
    @State private var heard: String = ""
    @State private var showingRokuSetup = false
    @State private var mediaState: RokuController.MediaState? = nil
    @State private var polledAt: Date? = nil

    // Voice control
    @State private var recorder = AudioRecorder()
    @State private var voiceState: VoiceState = .idle
    @State private var recordingStartedAt: Date? = nil

    enum VoiceState: Equatable {
        case idle
        case recording
        case thinking
        case denied
    }

    var body: some View {
        Page(spacing: 24, horizontalPadding: 48, topPadding: 24) {
            ContextStrip(says: says, heard: heard)

            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if presence.alertActive {
                    presenceAlertBanner
                }
            }

            ForEach(alerter.inbox) { msg in
                CaregiverMessageCard(
                    message: msg,
                    displayName: alerter.displayName(forTelegramName: msg.senderName)
                ) {
                    Task { await alerter.acknowledge(msg) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !stopped {
                nowPlayingHero
                voiceButton
                rewindIntents
            } else {
                stoppedConfirmation
            }

            Text("Your shows")
                .font(HearthFont.serif(size: 36, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(HearthColor.ink)
                .padding(.top, 12)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3),
                spacing: 28
            ) {
                ForEach(FavouritesData.all) { show in
                    favouriteTile(show)
                }
            }

            HStack(spacing: 12) {
                Icon(name: "heart", size: 22, color: HearthColor.ember)
                Text("Your shows are always here. Hearth keeps your place — nothing is ever lost.")
                    .font(HearthFont.sans(size: 20, weight: .bold))
                    .foregroundStyle(HearthColor.inkSoft)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.cardWarm))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))

            TimelineView(.periodic(from: .now, by: 15)) { _ in
                wellnessPill
            }
        }
        .sheet(isPresented: $showingRokuSetup) {
            RokuSetupSheet().environment(roku)
        }
        .sheet(isPresented: $showingWellness) {
            WellnessSheet(
                presence: presence,
                alerter: alerter,
                onDismiss: { showingWellness = false }
            )
        }
        .task {
            presence.attach(gemma: gemma)
            presence.attach(alerter: alerter)
        }
        .task {
            // Anchor cursor so messages sent BEFORE the app opened don't
            // suddenly appear when polling starts. Then long-poll.
            await alerter.anchorInboxToNow()
            while !Task.isCancelled {
                await alerter.pollInbox()
                // Each new inbound note becomes a cue so the voice
                // orchestrator can answer questions about it later.
                for msg in alerter.inbox where !ingestedInboxIds.contains(msg.id) {
                    ingestedInboxIds.insert(msg.id)
                    await ingestMessageAsCue(msg)
                }
                // pollInbox uses Telegram's long-poll timeout=25; the
                // sleep below is just a safety yield for cancellation.
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: alerter.inbox.map(\.id))
        .task {
            // Poll Roku state while screen is visible. Cancels on disappear.
            while !Task.isCancelled {
                let state = await roku.mediaPlayerState()
                mediaState = state
                polledAt = Date()
                if let s = state {
                    paused = (s.status == .paused)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: Roku status pill
    private var rokuStatusPill: some View {
        Button { showingRokuSetup = true } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(rokuDotColor)
                    .frame(width: 8, height: 8)
                Text(rokuLabel)
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

    private var rokuDotColor: Color {
        switch roku.status {
        case .ready: return HearthColor.sageDeep
        case .unreachable, .error: return HearthColor.ember
        case .unconfigured: return HearthColor.inkMute
        }
    }

    private var rokuLabel: String {
        switch roku.status {
        case .ready: return "TV ready"
        case .unreachable: return "TV unreachable"
        case .error: return "TV: error"
        case .unconfigured: return "Connect TV"
        }
    }

    // MARK: Now playing
    private var nowPlayingHero: some View {
        HStack(alignment: .top, spacing: 28) {
            heroPoster
                .frame(width: 380, height: 320)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("YOU ARE WATCHING")
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(HearthColor.inkMute)
                    Spacer()
                    rokuStatusPill
                }
                Text(playing.title)
                    .font(HearthFont.serif(size: 64, weight: .medium))
                    .tracking(-1.0)
                    .foregroundStyle(HearthColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Icon(name: "television-simple", size: 28, color: HearthColor.ember)
                    Text(playing.episode)
                        .font(HearthFont.sans(size: 28, weight: .bold))
                        .foregroundStyle(HearthColor.inkSoft)
                }
                .padding(.top, 6)
                playbackStrip

                HStack(spacing: 12) {
                    LabeledTransportButton(icon: "arrow-counter-clockwise", label: "Back") {
                        backNudge()
                    }
                    LabeledTransportButton(
                        icon: paused ? "play" : "pause",
                        label: paused ? "Play" : "Pause",
                        kind: .primary,
                        big: true
                    ) {
                        togglePause()
                    }
                    LabeledTransportButton(icon: "skip-forward", label: "Next") {
                        nextEpisode()
                    }
                    LabeledTransportButton(icon: "speaker-high", label: "Volume") {
                        volumeUp()
                    }
                }
                .padding(.top, 22)

                Button(action: stopWatching) {
                    HStack(spacing: 12) {
                        Icon(name: "x-circle", size: 28, color: HearthColor.inkSoft)
                        Text("Stop watching")
                            .font(HearthFont.sans(size: 22, weight: .bold))
                            .foregroundStyle(HearthColor.ink)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(HearthColor.paperDeep))
                    .overlay(Capsule().stroke(HearthColor.border, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 36).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 36).stroke(HearthColor.ember, lineWidth: 3))
    }

    // MARK: Rewind chips
    private var rewindIntents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IF YOU MISSED SOMETHING")
                .font(HearthFont.sans(size: 16, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(HearthColor.inkMute)

            // Wrap row of chips
            FlowingHStack(spacing: 12) {
                IntentChip(icon: "arrow-counter-clockwise", label: "I missed that") {
                    bigRewind()
                }
                IntentChip(icon: "rewind", label: "Go back a little") {
                    backNudge()
                }
                IntentChip(icon: "arrow-clockwise", label: "Too far") {
                    forwardNudge()
                }
                IntentChip(icon: "question", label: "What's happening?") {
                    Task { await whatsHappening() }
                }
            }
        }
    }

    // MARK: Stopped confirmation
    private var stoppedConfirmation: some View {
        HStack(spacing: 16) {
            Icon(name: "check-circle", size: 32, color: HearthColor.sageDeep)
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved your place in \(playing.title).")
                    .font(HearthFont.serif(size: 26, weight: .medium))
                    .foregroundStyle(HearthColor.ink)
                Text("Pick another show below whenever you'd like.")
                    .font(HearthFont.sans(size: 18))
                    .foregroundStyle(HearthColor.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 20).fill(HearthColor.cardWarm))
        .overlay(
            HStack(spacing: 0) {
                Rectangle().fill(HearthColor.sageDeep).frame(width: 6)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        )
    }

    // MARK: Favourite tile
    // All tiles are forced to a uniform 2:3 portrait aspect (standard show-poster ratio),
    // so landscape posters get a deliberate center-crop rather than warping the grid.
    private func favouriteTile(_ show: Show) -> some View {
        let isPlaying = !stopped && show == playing
        return Button(action: { playShow(show) }) {
            VStack(spacing: 14) {
                ZStack {
                    ZStack {
                        Color(hex: 0x2A241C)
                        Image(show.imageName)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                    // bookmark — bottom-left
                    HStack(spacing: 6) {
                        Icon(name: "bookmark-simple", size: 14, color: .white)
                        Text(show.resume)
                            .font(HearthFont.sans(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: 240, alignment: .bottomLeading)

                    // playing now — top-left
                    if isPlaying {
                        HStack(spacing: 8) {
                            Circle().fill(.white).frame(width: 8, height: 8)
                            Text("PLAYING NOW")
                                .font(HearthFont.sans(size: 14, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(HearthColor.ember))
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topLeading)
                    }

                    // platform badge — top-right
                    if let platform = show.platform {
                        Text(platform.shortName)
                            .font(HearthFont.sans(size: 12, weight: .bold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topTrailing)
                    }
                }
                .frame(height: 240)
                .opacity(stopped || isPlaying ? 1 : 0.62)
                .shadow(color: isPlaying ? HearthColor.ember.opacity(0.65) : .clear,
                        radius: 14, x: 0, y: 0)
                .shadow(color: isPlaying ? HearthColor.ember.opacity(0.45) : .clear,
                        radius: 28, x: 0, y: 0)
                Text(show.title)
                    .font(HearthFont.serif(size: 28, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(isPlaying ? HearthColor.emberDeep : HearthColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(show.episode)
                    .font(HearthFont.sans(size: 16, weight: .bold))
                    .foregroundStyle(HearthColor.inkMute)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    // Hero poster — uses GeometryReader so the image is constrained both
    // for rendering and layout. Parent supplies size via .frame(width:height:).
    private var heroPoster: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0x2A241C)
                Image(playing.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                HStack(spacing: 6) {
                    Icon(name: "bookmark-simple", size: 16, color: .white)
                    Text(playing.resume)
                        .font(HearthFont.sans(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(14)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: Actions
    // Each action narrates locally AND fires the Roku call. Narration stays
    // even if the TV is unreachable so the screen still reads coherently.

    private func togglePause() {
        let wasPaused = paused
        paused.toggle()
        heard = wasPaused ? "play" : "pause"
        says = wasPaused
            ? "Playing again. You're back where you left off in \(playing.title)."
            : "Paused. We can come back any time."
        Task {
            await roku.play()
            // Re-poll immediately so the button reflects what the Roku
            // actually did (handles the case where state is stale).
            try? await Task.sleep(for: .milliseconds(500))
            if let s = await roku.mediaPlayerState() {
                mediaState = s
                paused = (s.status == .paused)
            }
        }
    }

    private func stopWatching() {
        let wasTitle = playing.title
        stopped = true
        paused = false
        heard = "stop watching"
        says = "All done with \(wasTitle). It's saved right where you left off."
        Task { await roku.home() }
    }

    private func playShow(_ show: Show) {
        playing = show
        paused = false
        stopped = false
        heard = "watch \(show.title)"
        let resumeLine = show.resume == "Start of episode"
            ? "Starting from the beginning."
            : "You're \(show.resume)."
        says = "Putting on \(show.title). \(show.episode). \(resumeLine)"
        Task { await roku.launchShow(show) }
    }

    private func speak(_ heardText: String, _ saysText: String) {
        heard = heardText
        says = saysText
    }

    // Intent helpers — narration + Roku side-effect together.
    private func backNudge() {
        speak("go back a little", "I went back about ten seconds. Nothing was lost.")
        Task { await roku.instantReplay(times: 1) }
    }
    private func bigRewind() {
        speak("I missed that", "I went back about thirty seconds. You haven't lost anything.")
        Task { await roku.instantReplay(times: 3) }
    }
    private func forwardNudge() {
        speak("too far", "Coming forward a little. You're back where you wanted.")
        Task { await roku.fastForward() }
    }
    private func volumeUp() {
        speak("louder", "A little louder.")
        Task { await roku.volumeUp() }
    }

    private func nextEpisode() {
        speak("next episode", "Looking for the next episode…")
        Task {
            await roku.nextEpisode()
            try? await Task.sleep(for: .milliseconds(800))
            mediaState = await roku.mediaPlayerState()
        }
    }

    // MARK: Voice control
    // Big tap-to-talk button: tap once to start recording, tap again to stop
    // early, or wait for the 8-second cap. Recording → Gemma audio inference
    // → parsed intent → dispatch.
    private var voiceButton: some View {
        Button {
            Task { await voiceButtonTapped() }
        } label: {
            HStack(spacing: 16) {
                Icon(name: voiceIconName, size: 36, color: voiceFgColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voicePrimaryLabel)
                        .font(HearthFont.sans(size: 24, weight: .bold))
                        .foregroundStyle(voiceFgColor)
                    Text(voiceSecondaryLabel)
                        .font(HearthFont.sans(size: 16, weight: .bold))
                        .foregroundStyle(voiceFgColor.opacity(0.7))
                }
                Spacer()
                if voiceState == .recording, let started = recordingStartedAt {
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        let elapsed = max(0, ctx.date.timeIntervalSince(started))
                        let remaining = max(0, Self.recordCapSeconds - elapsed)
                        Text(String(format: "%.0fs", remaining))
                            .font(HearthFont.sans(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(voiceFgColor)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28).fill(voiceBgColor))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(voiceBgColor.opacity(0.4), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(voiceState == .thinking)
    }

    private static let recordCapSeconds: TimeInterval = 8.0

    private var voiceIconName: String {
        switch voiceState {
        case .idle:      return "microphone"
        case .recording: return "microphone-fill"
        case .thinking:  return "circle-notch"
        case .denied:    return "microphone-slash"
        }
    }
    private var voicePrimaryLabel: String {
        switch voiceState {
        case .idle:      return "Tap to talk"
        case .recording: return "Listening…"
        case .thinking:  return "Thinking…"
        case .denied:    return "Microphone is off"
        }
    }
    private var voiceSecondaryLabel: String {
        if gemma.status != .ready {
            return "Set up companion to use voice"
        }
        switch voiceState {
        case .idle:      return "Try \u{201C}pause\u{201D}, \u{201C}louder\u{201D}, or \u{201C}put on Seinfeld\u{201D}"
        case .recording: return "Tap again or wait — I'll stop on my own"
        case .thinking:  return "Hearth is figuring out what you said"
        case .denied:    return "Enable microphone access in Settings"
        }
    }
    private var voiceBgColor: Color {
        switch voiceState {
        case .idle:      return HearthColor.ember
        case .recording: return HearthColor.emberDeep
        case .thinking:  return HearthColor.honeyDeep
        case .denied:    return HearthColor.paperDeep
        }
    }
    private var voiceFgColor: Color {
        voiceState == .denied ? HearthColor.inkSoft : .white
    }

    private func voiceButtonTapped() async {
        switch voiceState {
        case .recording:
            await finishRecording()
        case .idle:
            await startRecording()
        case .thinking, .denied:
            return
        }
    }

    private func startRecording() async {
        guard gemma.status == .ready else {
            speak("voice", "The companion isn't set up yet. Open the Home screen to download it.")
            return
        }
        let ok = await recorder.start()
        if !ok {
            voiceState = .denied
            speak("voice", "I can't hear — please allow microphone access in Settings.")
            return
        }
        voiceState = .recording
        recordingStartedAt = Date()
        speak("listening", "I'm listening — what would you like?")
        // Auto-stop after the cap so dementia users never get stuck recording.
        Task {
            try? await Task.sleep(for: .seconds(Self.recordCapSeconds))
            if voiceState == .recording {
                await finishRecording()
            }
        }
    }

    private func finishRecording() async {
        guard voiceState == .recording else { return }
        voiceState = .thinking
        recordingStartedAt = nil
        speak("thinking", "Let me see what you said…")
        guard let data = recorder.stop() else {
            voiceState = .idle
            speak("voice", "I didn't catch that — try again?")
            return
        }

        // Snapshot the world so Gemma can plan in one shot.
        let titles = FavouritesData.all.map(\.title)
        let now = Date()
        let state = HearthGemma.VoiceWorldState(
            rokuStatus: rokuStatusString(),
            activeShowTitle: playing.title,
            activeEpisode: playing.episode,
            playbackState: mediaState.map { stateLabel($0.status) },
            positionSeconds: mediaState?.positionSeconds,
            durationSeconds: mediaState?.durationSeconds,
            clock: Self.fmtTimeOfDay(now),
            dayOfWeek: Self.fmtDayOfWeek(now),
            weatherTemperature: "72°F"
        )

        let cueSpecs = cues.entries.filter(\.isLive).map {
            RokuToolKit.CueSpec(
                name: $0.name,
                keywords: $0.keywords,
                value: $0.value,
                schedule: $0.schedule,
                threshold: $0.threshold
            )
        }
        let plan = await gemma.planVoiceAction(
            audioData: data, state: state, showTitles: titles, cues: cueSpecs
        )
        voiceState = .idle
        await executePlan(plan)
    }

    // Orchestrator path. Runs each tool call in order, then narrates. Special
    // case: when Gemma emits `answerCue <name>`, we substitute the caregiver's
    // verbatim cue value for the narration — never let the model paraphrase a
    // medical/care answer.
    private func executePlan(_ plan: RokuToolKit.Plan) async {
        let executor = RokuToolExecutor(roku: roku, shows: FavouritesData.all)
        for call in plan.calls {
            await executor.execute(call)
            // Tiny gap between calls — keeps Roku happy when chaining keys.
            try? await Task.sleep(for: .milliseconds(120))
        }
        // Optimistic local mirroring for the most common single-call cases so
        // the screen reflects the action before the next poll lands.
        if plan.calls.contains(where: { $0.name == "play" }) {
            paused.toggle()
        }
        if plan.calls.contains(where: { $0.name == "home" }) {
            stopped = true
        }
        // Refresh from Roku to correct any optimistic guess.
        if let s = await roku.mediaPlayerState() {
            mediaState = s
            polledAt = Date()
            paused = (s.status == .paused)
        }

        let narration = plan.narration?.isEmpty == false
            ? plan.narration!
            : (plan.calls.isEmpty
                ? "I didn't quite catch that — try again?"
                : "Done.")
        speak("voice", narration)
    }

    private func rokuStatusString() -> String {
        switch roku.status {
        case .ready: return "ready"
        case .unreachable: return "unreachable"
        case .error: return "error"
        case .unconfigured: return "unconfigured"
        }
    }

    // MARK: Playback strip
    // Shows position / duration / progress / remaining from the Roku, ticking
    // every second between 5-second polls (we extrapolate forward while
    // status == .playing). Honest about every other state — paused, stopped,
    // unreachable, no playback — so the screen never lies.
    private var playbackStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let live = liveSnapshot(at: ctx.date)
            VStack(alignment: .leading, spacing: 10) {
                if let position = live.position, let duration = live.duration {
                    HStack(spacing: 14) {
                        Text(Self.fmtClock(position))
                            .font(HearthFont.sans(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(HearthColor.sageDeep)
                        progressBar(position: position, duration: duration)
                        Text(Self.fmtClock(duration))
                            .font(HearthFont.sans(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(HearthColor.inkSoft)
                    }
                }
                HStack(spacing: 10) {
                    Icon(name: "bookmark-simple", size: 18, color: HearthColor.sageDeep)
                    Text(live.summary)
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(HearthColor.sageDeep)
                }
            }
        }
    }

    private func progressBar(position: Int, duration: Int) -> some View {
        let frac = duration > 0 ? min(1.0, Double(position) / Double(duration)) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(HearthColor.borderSoft)
                Capsule().fill(HearthColor.sageDeep)
                    .frame(width: max(6, geo.size.width * frac))
            }
        }
        .frame(height: 8)
    }

    // Snapshot we render — position is extrapolated forward 1 sec at a time
    // while playing so the timer feels alive between polls.
    private struct LiveSnapshot {
        let position: Int?     // seconds
        let duration: Int?     // seconds
        let summary: String    // single line: state + percent + remaining
    }

    private func liveSnapshot(at now: Date) -> LiveSnapshot {
        // No connection / no media — show mock fallback so the card still reads.
        guard let media = mediaState else {
            if roku.status == .unconfigured {
                return LiveSnapshot(position: nil, duration: nil,
                                    summary: "Connect a TV to see live playback")
            }
            if roku.status == .unreachable {
                return LiveSnapshot(position: nil, duration: nil,
                                    summary: "TV not reachable — showing last known")
            }
            return LiveSnapshot(position: nil, duration: nil,
                                summary: "You're \(playing.resume)")
        }

        // No position/duration → nothing's playing yet (idle, title page, etc).
        guard let basePos = media.positionSeconds, let duration = media.durationSeconds else {
            return LiveSnapshot(position: nil, duration: nil,
                                summary: stateSummary(media.status))
        }

        let elapsed: Int = {
            guard media.status == .playing, let polledAt else { return 0 }
            return max(0, Int(now.timeIntervalSince(polledAt)))
        }()
        let position = min(duration, basePos + elapsed)
        let remaining = max(0, duration - position)
        let percent = duration > 0 ? (position * 100 / duration) : 0
        let summary = "\(stateSummary(media.status))  •  \(percent)%  •  \(Self.fmtClock(remaining)) left"
        return LiveSnapshot(position: position, duration: duration, summary: summary)
    }

    private func stateSummary(_ s: RokuController.MediaState.Status) -> String {
        switch s {
        case .playing:   return "Playing"
        case .paused:    return "Paused"
        case .buffering: return "Loading"
        case .stopped:   return "Stopped"
        case .idle:      return "Nothing is playing right now"
        }
    }

    private static func fmtTimeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func fmtDayOfWeek(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private static func fmtClock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // "What's happening?" — narrate the TV's real state. Path:
    //   1. Show "Let me see…" immediately so the chip feels alive.
    //   2. Ask the Roku for /query/media-player (position + duration + state).
    //   3. If Gemma is ready, feed it the real state; otherwise build a plain
    //      truthful sentence from the same data.
    //   4. If the Roku is unreachable, fall back to mock copy so the screen
    //      still reads coherently.
    private func whatsHappening() async {
        speak("what's happening?", "Let me see…")
        let media = await roku.mediaPlayerState()

        if let media, gemma.status == .ready {
            let ctx = HearthGemma.TVContext(
                title: playing.title,
                episode: playing.episode,
                stateLabel: stateLabel(media.status),
                positionSeconds: media.positionSeconds,
                durationSeconds: media.durationSeconds
            )
            if let line = await gemma.generateTVStateLine(ctx), !line.isEmpty {
                says = line
                return
            }
        }
        says = composeWhatsHappening(media: media)
    }

    private func composeWhatsHappening(media: RokuController.MediaState?) -> String {
        guard let media else {
            return "You're watching \(playing.title). \(playing.episode). You're \(playing.resume)."
        }
        let state = stateLabel(media.status)
        if let pos = media.positionSeconds, let dur = media.durationSeconds, dur > 0 {
            let posMin = max(0, pos / 60)
            let remaining = max(0, (dur - pos) / 60)
            return "You're \(posMin) minute\(posMin == 1 ? "" : "s") into \(playing.title) — "
                + "\(state), about \(remaining) minute\(remaining == 1 ? "" : "s") left."
        }
        return "You're watching \(playing.title). \(playing.episode). \(state.capitalized)."
    }

    private func stateLabel(_ s: RokuController.MediaState.Status) -> String {
        switch s {
        case .playing:   return "playing"
        case .paused:    return "paused"
        case .buffering: return "loading"
        case .stopped, .idle: return "stopped"
        }
    }

    // MARK: - Inbound notes → cues
    //
    // Turn each caregiver Telegram note into a cue so the Watch voice
    // orchestrator can answer "where is Sarah?" / "what's for dinner?"
    // later. Gemma reads the note and predicts likely follow-up questions
    // — those become the cue's "Hears" keywords. The verbatim message is
    // the cue's value, prefixed with sender + timestamp for grounding.
    //
    // One rolling cue per sender — a new note from Sarah replaces her
    // previous one, so the catalog doesn't bloat over a long evening of
    // back-and-forth.
    private func ingestMessageAsCue(_ msg: CaregiverAlerter.InboundMessage) async {
        let displayName = alerter.displayName(forTelegramName: msg.senderName)
        let stamp = Self.fmtNoteTime(msg.sentAt)
        let cueName = "Note from \(displayName)"

        // Predicted questions from Gemma; fall back to a small generic set
        // if Gemma isn't ready (still loading, etc.) so the cue is at
        // least somewhat reachable.
        let predicted = await gemma.extractQuestionsForCue(
            message: msg.text,
            sender: displayName
        )
        let keywords = predicted ?? [
            "where is \(displayName.lowercased())",
            "when is \(displayName.lowercased()) coming home",
            "is \(displayName.lowercased()) home",
            "what did \(displayName.lowercased()) say",
            "any messages",
            "any news"
        ]

        let value = "\(displayName) sent this at \(stamp): \"\(msg.text)\""

        // Replace any prior note from the same sender so we keep just the
        // latest plan (case-insensitive name match).
        let priorIds = cues.entries
            .filter { $0.name.lowercased() == cueName.lowercased() }
            .map(\.id)
        for id in priorIds { cues.delete(id) }

        var entry = CueEntry.blank
        entry.name = cueName
        entry.keywords = keywords
        entry.value = value
        entry.imageName = "heart"
        // Family notes go stale after a day — "home by 8 tonight" should
        // not still be on the catalog two mornings later.
        entry.expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        cues.upsert(entry)
    }

    private static func fmtNoteTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    // MARK: - Wellness (presence monitor surface)

    // Compact pill at the bottom of the page. Three states:
    //   off    — gentle invitation to enable monitoring
    //   on/ok  — green dot, "Watching · last seen 12m ago"
    //   alert  — ember/red, "Not seen for 2h 14m"
    private var wellnessPill: some View {
        HStack {
            Spacer()
            Button { showingWellness = true } label: {
                HStack(spacing: 12) {
                    Circle().fill(wellnessDotColor).frame(width: 10, height: 10)
                    Text(wellnessLabel)
                        .font(HearthFont.sans(size: 16, weight: .bold))
                        .foregroundStyle(HearthColor.ink)
                    Icon(name: "pencil", size: 13, color: HearthColor.inkMute)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(HearthColor.card))
                .overlay(Capsule().stroke(HearthColor.borderSoft, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 12)
    }

    private var wellnessDotColor: Color {
        if !presence.isMonitoring { return HearthColor.inkMute }
        if presence.alertActive { return .red }
        if presence.lastSeen != nil { return HearthColor.sageDeep }
        return HearthColor.ember
    }

    private var wellnessLabel: String {
        if !presence.isMonitoring { return "Wellness sensing off" }
        if presence.alertActive {
            return "Not seen for \(Self.fmtElapsed(presence.secondsSinceLastSeen ?? 0))"
        }
        if let secs = presence.secondsSinceLastSeen {
            if secs < 60 { return "Watching · just now" }
            return "Watching · last seen \(Self.fmtElapsed(secs)) ago"
        }
        return "Watching · waiting for a sample"
    }

    // Big banner at the top of the page when the absence threshold has
    // tripped. Persistent (no auto-dismiss) — meant to be impossible to
    // miss when the caregiver walks past the iPad.
    private var presenceAlertBanner: some View {
        Button { showingWellness = true } label: {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.15)).frame(width: 56, height: 56)
                    Icon(name: "x-circle", size: 32, color: .red)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOBODY SEEN IN THE ROOM")
                        .font(HearthFont.sans(size: 13, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.red)
                    Text("Hearth hasn't spotted anyone for \(Self.fmtElapsed(presence.secondsSinceLastSeen ?? 0)).")
                        .font(HearthFont.serif(size: 24, weight: .medium))
                        .foregroundStyle(HearthColor.ink)
                }
                Spacer(minLength: 0)
                Icon(name: "pencil", size: 18, color: HearthColor.inkMute)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.red.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.red.opacity(0.5), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private static func fmtElapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let mr = m % 60
        return mr == 0 ? "\(h)h" : "\(h)h \(mr)m"
    }
}

// Simple flowing-wrap HStack so the intent chips wrap on narrow widths.
struct FlowingHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Native SwiftUI horizontal wrapping uses Layout in iOS 16+; fall back to
        // a wrap-aware HStack with `LazyVGrid` is wrong (it's a grid). For now,
        // a plain HStack is fine on iPad widths where 4 chips fit; if needed we
        // can swap to a proper Flow layout later.
        HStack(spacing: spacing) { content() }
    }
}

// MARK: - Wellness sheet
//
// Caregiver-facing controls for the presence sensing loop. Toggle the
// loop on/off, pick how often Hearth checks the room, pick how long
// "missing" needs to be before it counts as an alert, and scrub through
// recent samples.
struct WellnessSheet: View {
    let presence: PresenceMonitor
    let alerter: CaregiverAlerter
    let onDismiss: () -> Void

    @State private var ticker = Date()
    @State private var sendingTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusCard
                controlsCard
                caregiverAlertsCard
                samplesCard
            }
            .padding(28)
        }
        .background(HearthColor.paper.ignoresSafeArea())
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            ticker = Date()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(HearthColor.ember.opacity(0.12)).frame(width: 56, height: 56)
                Icon(name: "heart", size: 28, color: HearthColor.ember)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Wellness sensing")
                    .font(HearthFont.serif(size: 30, weight: .medium))
                    .foregroundStyle(HearthColor.ink)
                Text("Hearth quietly checks the room and alerts you if no one's been seen in a while.")
                    .font(HearthFont.sans(size: 15))
                    .foregroundStyle(HearthColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onDismiss) {
                Icon(name: "x-circle", size: 28, color: HearthColor.inkMute)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusCard: some View {
        let lastSeenText: String = {
            guard let last = presence.lastSeen else { return "Never" }
            return "\(Self.fmtElapsed(ticker.timeIntervalSince(last))) ago"
        }()
        let lastSampleText: String = {
            guard let when = presence.lastSampleAt else { return "Not yet" }
            return "\(Self.fmtElapsed(ticker.timeIntervalSince(when))) ago · \(presence.lastSampleResult.label)"
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle().fill(headerDot).frame(width: 14, height: 14)
                Text(headerTitle.uppercased())
                    .font(HearthFont.sans(size: 13, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(headerColor)
            }
            HStack(spacing: 24) {
                statBlock(label: "LAST SEEN", value: lastSeenText)
                statBlock(label: "LAST SAMPLE", value: lastSampleText)
                statBlock(label: "SAMPLES", value: "\(presence.samples.count)")
            }
            if presence.cameraDenied {
                Text("Camera permission was denied. Wellness sensing can't run.")
                    .font(HearthFont.sans(size: 14))
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(headerColor.opacity(0.4), lineWidth: 2))
    }

    private var headerDot: Color {
        if !presence.isMonitoring { return HearthColor.inkMute }
        if presence.alertActive { return .red }
        return HearthColor.sageDeep
    }
    private var headerColor: Color {
        if !presence.isMonitoring { return HearthColor.inkMute }
        if presence.alertActive { return .red }
        return HearthColor.sageDeep
    }
    private var headerTitle: String {
        if !presence.isMonitoring { return "Sensing is off" }
        if presence.alertActive { return "Alert · nobody seen recently" }
        return "All good · room is occupied"
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HearthFont.sans(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(HearthColor.inkMute)
            Text(value)
                .font(HearthFont.serif(size: 20, weight: .medium))
                .foregroundStyle(HearthColor.ink)
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: Binding(
                get: { presence.isMonitoring },
                set: { on in on ? presence.start() : presence.stop() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch the room")
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(HearthColor.ink)
                    Text("The camera blinks for about a second per sample.")
                        .font(HearthFont.sans(size: 14))
                        .foregroundStyle(HearthColor.inkSoft)
                }
            }
            .tint(HearthColor.ember)

            Divider().background(HearthColor.borderSoft)

            VStack(alignment: .leading, spacing: 10) {
                Text("CHECK EVERY")
                    .font(HearthFont.sans(size: 12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HearthColor.inkMute)
                HStack(spacing: 10) {
                    intervalChip(label: "30s", seconds: 30)
                    intervalChip(label: "1m", seconds: 60)
                    intervalChip(label: "5m", seconds: 300)
                    intervalChip(label: "15m", seconds: 900)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("ALERT AFTER")
                    .font(HearthFont.sans(size: 12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HearthColor.inkMute)
                HStack(spacing: 10) {
                    thresholdChip(label: "2m", seconds: 120)
                    thresholdChip(label: "5m", seconds: 300)
                    thresholdChip(label: "30m", seconds: 30 * 60)
                    thresholdChip(label: "1h", seconds: 60 * 60)
                    thresholdChip(label: "2h", seconds: 2 * 60 * 60)
                }
            }

            HStack {
                Spacer()
                HearthButton("Check now", kind: .secondary, icon: "camera") {
                    Task { await presence.sampleNow() }
                }
                .opacity(presence.sampling ? 0.5 : 1)
                .disabled(presence.sampling)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    private func intervalChip(label: String, seconds: TimeInterval) -> some View {
        let active = Int(presence.sampleInterval) == Int(seconds)
        return Button {
            presence.setSampleInterval(seconds)
        } label: {
            Text(label)
                .font(HearthFont.sans(size: 15, weight: .bold))
                .foregroundStyle(active ? .white : HearthColor.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(active ? HearthColor.ember : HearthColor.cardWarm))
        }
        .buttonStyle(.plain)
    }

    private func thresholdChip(label: String, seconds: TimeInterval) -> some View {
        let active = Int(presence.absenceThreshold) == Int(seconds)
        return Button {
            presence.setAbsenceThreshold(seconds)
        } label: {
            Text(label)
                .font(HearthFont.sans(size: 15, weight: .bold))
                .foregroundStyle(active ? .white : HearthColor.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(active ? HearthColor.ember : HearthColor.cardWarm))
        }
        .buttonStyle(.plain)
    }

    private var caregiverAlertsCard: some View {
        @Bindable var bindable = alerter
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Icon(name: "phone", size: 18, color: HearthColor.ember)
                Text("CAREGIVER ALERTS · TELEGRAM")
                    .font(HearthFont.sans(size: 13, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HearthColor.ember)
                Rectangle().fill(HearthColor.ember.opacity(0.25)).frame(height: 1)
            }

            Text("When nobody's been seen for the alert window, Hearth pings a Telegram chat. Free, instant, rings the phone.")
                .font(HearthFont.sans(size: 14))
                .foregroundStyle(HearthColor.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("CAREGIVER NAME (SHOWN ON THE WATCH SCREEN)")
                    .font(HearthFont.sans(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HearthColor.inkMute)
                TextField("Sarah", text: $bindable.caregiverName)
                    .font(HearthFont.sans(size: 16))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BOT TOKEN")
                    .font(HearthFont.sans(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HearthColor.inkMute)
                SecureField("123456:ABC-DEF…", text: $bindable.botToken)
                    .font(HearthFont.sans(size: 16).monospaced())
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("CHAT ID")
                    .font(HearthFont.sans(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HearthColor.inkMute)
                TextField("123456789", text: $bindable.chatId)
                    .font(HearthFont.sans(size: 16).monospaced())
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(HearthColor.cardWarm))
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }

            HStack(spacing: 12) {
                statusLine
                Spacer()
                HearthButton(
                    sendingTest ? "Sending…" : "Send test",
                    kind: .primary,
                    icon: "sparkle"
                ) {
                    Task {
                        sendingTest = true
                        defer { sendingTest = false }
                        await alerter.send(
                            text: "✨ Hearth test — alerts are wired up. You'll hear from me if nobody's in the room."
                        )
                    }
                }
                .disabled(!alerter.isConfigured || sendingTest)
                .opacity(alerter.isConfigured && !sendingTest ? 1 : 0.5)
            }

            DisclosureGroup("How do I get these?") {
                Text("""
                1. On Telegram, search for @BotFather and start a chat.
                2. Send /newbot and follow the prompts. Copy the bot TOKEN it gives you.
                3. Open your new bot and send /start so it has a chat with you.
                4. Visit https://api.telegram.org/bot<TOKEN>/getUpdates in a browser. Find "chat":{"id": NUMBER, …} and copy that NUMBER as the CHAT ID.
                """)
                .font(HearthFont.sans(size: 13))
                .foregroundStyle(HearthColor.inkSoft)
                .lineSpacing(2)
                .padding(.top, 6)
            }
            .tint(HearthColor.ember)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    @ViewBuilder private var statusLine: some View {
        switch alerter.lastResult {
        case .never:
            Text(alerter.isConfigured ? "Ready · no message sent yet" : "Not configured")
                .font(HearthFont.sans(size: 13))
                .foregroundStyle(HearthColor.inkMute)
        case .success(let when):
            HStack(spacing: 6) {
                Icon(name: "check-circle", size: 14, color: HearthColor.sageDeep)
                Text("Sent · \(Self.fmtTime(when))")
                    .font(HearthFont.sans(size: 13))
                    .foregroundStyle(HearthColor.sageDeep)
            }
        case .failure(let msg, let when):
            HStack(spacing: 6) {
                Icon(name: "x-circle", size: 14, color: .red)
                Text("Failed · \(Self.fmtTime(when)) · \(msg)")
                    .font(HearthFont.sans(size: 13))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var samplesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECENT SAMPLES")
                .font(HearthFont.sans(size: 13, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(HearthColor.inkMute)
            if presence.samples.isEmpty {
                Text("Hearth hasn't taken any samples yet.")
                    .font(HearthFont.sans(size: 15))
                    .foregroundStyle(HearthColor.inkSoft)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presence.samples.suffix(12).reversed()) { sample in
                        HStack(spacing: 12) {
                            Icon(
                                name: sample.present ? "check-circle" : "x-circle",
                                size: 18,
                                color: sample.present ? HearthColor.sageDeep : HearthColor.inkMute
                            )
                            Text(Self.fmtTime(sample.timestamp))
                                .font(HearthFont.sans(size: 15, weight: .bold).monospacedDigit())
                                .foregroundStyle(HearthColor.ink)
                            Text(sample.present ? "Person in the room" : "No one visible")
                                .font(HearthFont.sans(size: 15))
                                .foregroundStyle(HearthColor.inkSoft)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(HearthColor.card))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    private static func fmtElapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let mr = m % 60
        return mr == 0 ? "\(h)h" : "\(h)h \(mr)m"
    }

    private static func fmtTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f.string(from: d)
    }
}

// MARK: - Caregiver message card
//
// Personal note from the caregiver, surfaced full-width at the top of the
// Watch tab. Big serif so dad can read it without his glasses; "FROM
// SARAH · 5:42 PM" eyebrow so he knows who sent it; one big "Got it"
// button that dismisses the card AND sends a "✓ Read at 5:43 PM" back to
// Telegram so the daughter knows it landed.
private struct CaregiverMessageCard: View {
    let message: CaregiverAlerter.InboundMessage
    let displayName: String
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(HearthColor.ember.opacity(0.18)).frame(width: 44, height: 44)
                    Icon(name: "heart", size: 22, color: HearthColor.ember)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FROM \(displayName.uppercased()) · \(Self.fmtTime(message.sentAt))")
                        .font(HearthFont.sans(size: 13, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(HearthColor.ember)
                    Text("A note for you")
                        .font(HearthFont.serif(size: 22, weight: .medium))
                        .foregroundStyle(HearthColor.inkSoft)
                }
                Spacer()
            }

            Text(message.text)
                .font(HearthFont.serif(size: 36, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(HearthColor.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                HearthButton("Got it", kind: .primary, icon: "check", action: onAcknowledge)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(HearthColor.ember.opacity(0.5), lineWidth: 2))
    }

    private static func fmtTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

private extension PresenceMonitor.SampleResult {
    var label: String {
        switch self {
        case .unknown:           return "not yet"
        case .present:           return "person seen"
        case .absent:            return "no one visible"
        case .skipped(let why):  return "skipped (\(why))"
        }
    }
}

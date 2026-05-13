import SwiftUI

struct TVScreen: View {
    @Environment(RokuController.self) private var roku
    @Environment(HearthGemma.self) private var gemma
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
        }
        .sheet(isPresented: $showingRokuSetup) {
            RokuSetupSheet().environment(roku)
        }
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
        let state = HearthGemma.VoiceWorldState(
            rokuStatus: rokuStatusString(),
            activeShowTitle: playing.title,
            activeEpisode: playing.episode,
            playbackState: mediaState.map { stateLabel($0.status) },
            positionSeconds: mediaState?.positionSeconds,
            durationSeconds: mediaState?.durationSeconds
        )

        let plan = await gemma.planVoiceAction(
            audioData: data, state: state, showTitles: titles
        )
        voiceState = .idle
        await executePlan(plan)
    }

    // Run each tool call in order via RokuToolExecutor, then narrate. If the
    // model returned no calls and no narration, fall back to a gentle retry
    // prompt so the user always hears something back.
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

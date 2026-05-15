import Foundation
import Observation

// Watches the room. While monitoring is on and the app is foregrounded,
// every `sampleInterval` we ask the camera for one still and Gemma
// whether a person is visible. The answer updates `lastSeen` and the
// rolling sample log; if `now - lastSeen` exceeds `absenceThreshold`,
// `alertActive` flips on. Caregiver UI watches that flag.
//
// Phase 1 scope is "is a person here, yes/no" — enough to catch the
// classic "I haven't seen him in three hours" case. Phase 2 would add
// posture/agitation cues by asking Gemma a richer prompt.
@Observable @MainActor
final class PresenceMonitor {

    // Configurable
    var isMonitoring: Bool = false
    var sampleInterval: TimeInterval = 60         // demo default; real default ~ 300
    var absenceThreshold: TimeInterval = 5 * 60   // demo default; real default ~ 2 * 3600

    // State surfaced to the UI
    private(set) var lastSeen: Date?
    private(set) var lastSampleAt: Date?
    private(set) var lastSampleResult: SampleResult = .unknown
    private(set) var samples: [Sample] = []
    private(set) var sampling: Bool = false
    private(set) var cameraDenied: Bool = false

    private var loopTask: Task<Void, Never>?
    private weak var gemma: HearthGemma?
    private weak var alerter: CaregiverAlerter?

    // Edge-trigger state for caregiver alerts. We only fire on transitions
    // (clear → tripped, or tripped → cleared) so the alerter doesn't spam.
    private var lastAlertWasActive: Bool = false
    private var lastAbsenceStartedAt: Date?

    enum SampleResult: Equatable {
        case unknown          // not run yet
        case present
        case absent
        case skipped(String)  // camera busy / no permission / Gemma not ready
    }

    struct Sample: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let present: Bool
    }

    /// Whether the absence threshold has been tripped right now.
    var alertActive: Bool {
        guard isMonitoring else { return false }
        guard let lastSeen else { return false }   // never seen yet — don't alert
        return Date().timeIntervalSince(lastSeen) >= absenceThreshold
    }

    /// Seconds since we last confirmed presence (or nil if never).
    var secondsSinceLastSeen: TimeInterval? {
        lastSeen.map { Date().timeIntervalSince($0) }
    }

    func attach(gemma: HearthGemma) {
        self.gemma = gemma
    }

    func attach(alerter: CaregiverAlerter) {
        self.alerter = alerter
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        scheduleLoop()
    }

    func stop() {
        isMonitoring = false
        loopTask?.cancel()
        loopTask = nil
        sampling = false
    }

    func setSampleInterval(_ seconds: TimeInterval) {
        sampleInterval = max(15, seconds)
        if isMonitoring { restartLoop() }
    }

    func setAbsenceThreshold(_ seconds: TimeInterval) {
        absenceThreshold = max(60, seconds)
    }

    // Force one sample immediately (caregiver tapping "Check now").
    func sampleNow() async {
        await runOneSample()
    }

    // MARK: - Loop

    private func scheduleLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            // Take one sample right away so the UI doesn't sit on
            // "Not checked yet" for a full interval.
            await self?.runOneSample()
            while let self, self.isMonitoring, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.sampleInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.runOneSample()
            }
        }
    }

    private func restartLoop() {
        scheduleLoop()
    }

    private func runOneSample() async {
        guard isMonitoring else { return }
        guard let gemma else {
            lastSampleResult = .skipped("Gemma not attached")
            lastSampleAt = Date()
            return
        }
        if case .ready = gemma.status { } else {
            lastSampleResult = .skipped("Voice companion not ready")
            lastSampleAt = Date()
            return
        }

        sampling = true
        defer { sampling = false }

        let granted = await CameraTap.shared.requestPermission()
        guard granted else {
            cameraDenied = true
            lastSampleResult = .skipped("Camera permission denied")
            lastSampleAt = Date()
            return
        }
        cameraDenied = false

        guard let jpeg = await CameraTap.shared.snap() else {
            lastSampleResult = .skipped("Camera busy")
            lastSampleAt = Date()
            return
        }

        guard let present = await gemma.detectPresence(imageData: jpeg) else {
            lastSampleResult = .skipped("Gemma returned no answer")
            lastSampleAt = Date()
            return
        }

        let now = Date()
        lastSampleAt = now
        lastSampleResult = present ? .present : .absent
        samples.append(Sample(timestamp: now, present: present))
        // Keep the in-memory log bounded — 200 samples × 1 min ≈ 3 hours.
        if samples.count > 200 {
            samples.removeFirst(samples.count - 200)
        }
        if present {
            lastSeen = now
        }

        await dispatchAlertIfEdgeTriggered()
    }

    // Compare the current alertActive state to the last time we fired an
    // outbound notification. On false→true, send the alert. On true→false
    // (person came back), send the "all clear." No-op otherwise.
    private func dispatchAlertIfEdgeTriggered() async {
        let nowActive = alertActive
        guard let alerter, alerter.isConfigured else {
            lastAlertWasActive = nowActive
            return
        }

        if nowActive && !lastAlertWasActive {
            let duration = secondsSinceLastSeen.map(Self.fmtElapsed) ?? "a while"
            let stamp = Self.fmtClock(Date())
            await alerter.send(
                text: "🚨 Hearth alert — nobody seen in the room for \(duration) (as of \(stamp)). Please check in."
            )
            lastAbsenceStartedAt = Date()
        } else if !nowActive && lastAlertWasActive {
            let away = lastAbsenceStartedAt.map { Self.fmtElapsed(Date().timeIntervalSince($0)) } ?? "a while"
            let stamp = Self.fmtClock(Date())
            await alerter.send(
                text: "✅ Hearth — they're back in the room (was away \(away), now \(stamp))."
            )
        }
        lastAlertWasActive = nowActive
    }

    static func fmtElapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let mr = m % 60
        return mr == 0 ? "\(h)h" : "\(h)h \(mr)m"
    }

    static func fmtClock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

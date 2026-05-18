import SwiftUI

// One-time pairing flow: the user enters the Roku's LAN IP, we save it, then
// probe http://<ip>:8060/ to confirm. Mirrors GemmaSetupSheet shape.
struct RokuSetupSheet: View {
    @Environment(RokuController.self) private var roku
    @Environment(\.dismiss) private var dismiss

    @State private var ip: String = ""
    @State private var testing = false
    @State private var lastResult: TestResult = .none
    @State private var installedApps: [(name: String, id: String)] = []
    @State private var loadingApps = false
    @State private var showingDiagnostic = false
    @State private var diagLoading = false
    @State private var diagMedia: String = ""
    @State private var diagActiveApp: String = ""
    @State private var diagMediaParsed: RokuController.MediaState? = nil

    enum TestResult: Equatable { case none, success, failure }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                statusCard
                if lastResult == .success || !installedApps.isEmpty {
                    installedAppsCard
                }
                if roku.status == .ready {
                    diagnosticCard
                }
                instructions
                footer
            }
            .padding(36)
        }
        .background(HearthColor.paper.ignoresSafeArea())
        .onAppear { ip = roku.host ?? "" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Connect your TV")
            Text("Let Hearth turn on your shows.")
                .font(HearthFont.serif(size: 40, weight: .medium))
                .tracking(-0.6)
                .foregroundStyle(HearthColor.ink)
            Text("Hearth will send commands to your Roku TV over the home Wi-Fi. "
                 + "Type its address once and we'll remember it.")
                .font(HearthFont.sans(size: 20))
                .foregroundStyle(HearthColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            label("TV address")
            HStack(spacing: 12) {
                TextField("192.168.1.100", text: $ip)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(HearthFont.sans(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(HearthColor.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(HearthColor.paperDeep))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(HearthColor.border, lineWidth: 1))
            }

            switch lastResult {
            case .none:
                EmptyView()
            case .success:
                HStack(spacing: 10) {
                    Icon(name: "check-circle", size: 22, color: HearthColor.sageDeep)
                    Text("Connected to your TV.")
                        .font(HearthFont.sans(size: 18, weight: .bold))
                        .foregroundStyle(HearthColor.sageDeep)
                }
            case .failure:
                HStack(alignment: .top, spacing: 10) {
                    Icon(name: "x-circle", size: 22, color: HearthColor.ember)
                    Text("Couldn't reach the TV. Make sure it's on, on the same Wi-Fi, "
                         + "and that \u{201C}Control by mobile apps\u{201D} is enabled in "
                         + "Settings → System → Advanced.")
                        .font(HearthFont.sans(size: 17))
                        .foregroundStyle(HearthColor.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 14) {
                HearthButton(
                    testing ? "Testing…" : "Save and test",
                    kind: .primary,
                    icon: "check"
                ) {
                    Task { await save() }
                }
                .disabled(testing || ip.isEmpty)
                if lastResult == .success {
                    HearthButton("Done", kind: .secondary) { dismiss() }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    // Shows what's actually installed on the Roku so we can sanity-check the
    // platform mappings. Each row: "Netflix — 12". Highlights apps Hearth
    // currently references.
    private var installedAppsCard: some View {
        let referencedIds = Set([
            Platforms.netflix, Platforms.max, Platforms.hulu, Platforms.disneyPlus,
            Platforms.primeVideo, Platforms.peacock, Platforms.paramount, Platforms.appleTV
        ].map { String($0.rokuAppId) })

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                label("Installed apps on your TV")
                Spacer()
                if loadingApps {
                    ProgressView().tint(HearthColor.ember)
                }
            }
            if installedApps.isEmpty && !loadingApps {
                Text("Couldn't read the app list.")
                    .font(HearthFont.sans(size: 17))
                    .foregroundStyle(HearthColor.inkSoft)
            }
            ForEach(installedApps, id: \.id) { app in
                let used = referencedIds.contains(app.id)
                HStack {
                    Text(app.name)
                        .font(HearthFont.sans(size: 18, weight: used ? .bold : .regular))
                        .foregroundStyle(HearthColor.ink)
                    Spacer()
                    Text("ID \(app.id)")
                        .font(HearthFont.sans(size: 14).monospacedDigit())
                        .foregroundStyle(HearthColor.inkMute)
                    if used {
                        Icon(name: "check-circle", size: 18, color: HearthColor.sageDeep)
                    }
                }
            }
            Text("Hearth opens the bold apps for your shows. If a show belongs to an app that isn't installed (or has a different ID here), tell me and I'll fix the mapping.")
                .font(HearthFont.sans(size: 14))
                .foregroundStyle(HearthColor.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    // Diagnostic — shows every field Roku will hand back about the active
    // app + media player. Useful both for verifying state and for spotting
    // anything we could read but currently don't.
    private var diagnosticCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                label("What your TV is doing right now")
                Spacer()
                HearthButton(diagLoading ? "Reading…" : "Refresh", kind: .secondary, icon: "arrows-clockwise") {
                    Task { await refreshDiagnostic() }
                }
                .disabled(diagLoading)
            }

            if let m = diagMediaParsed {
                VStack(alignment: .leading, spacing: 6) {
                    diagRow("State", stateLabel(m.status))
                    diagRow("Position", m.positionSeconds.map { fmtClock($0) } ?? "—")
                    diagRow("Duration", m.durationSeconds.map { fmtClock($0) } ?? "—")
                    if let pos = m.positionSeconds, let dur = m.durationSeconds, dur > 0 {
                        diagRow("Progress", "\(pos * 100 / dur)% through")
                        diagRow("Remaining", fmtClock(max(0, dur - pos)))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(HearthColor.paperDeep))
            }

            if !diagActiveApp.isEmpty {
                Text("Active app (raw)")
                    .font(HearthFont.sans(size: 16, weight: .bold))
                    .foregroundStyle(HearthColor.inkMute)
                Text(diagActiveApp)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HearthColor.inkSoft)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(HearthColor.paperDeep))
                    .textSelection(.enabled)
            }

            if !diagMedia.isEmpty {
                Text("Media player (raw)")
                    .font(HearthFont.sans(size: 16, weight: .bold))
                    .foregroundStyle(HearthColor.inkMute)
                Text(diagMedia)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HearthColor.inkSoft)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(HearthColor.paperDeep))
                    .textSelection(.enabled)
            }

            Text("Note: Roku does NOT expose episode title, season/episode number, "
                 + "show identity inside the streaming app, watch history, cast, or summary. "
                 + "Those live entirely inside Netflix/Hulu/etc.")
                .font(HearthFont.sans(size: 14))
                .foregroundStyle(HearthColor.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(HearthColor.borderSoft, lineWidth: 1))
        .task { await refreshDiagnostic() }
    }

    private func diagRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(HearthFont.sans(size: 15, weight: .bold))
                .foregroundStyle(HearthColor.inkMute)
                .frame(width: 110, alignment: .leading)
            Text(v)
                .font(HearthFont.sans(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(HearthColor.ink)
            Spacer()
        }
    }

    private func stateLabel(_ s: RokuController.MediaState.Status) -> String {
        switch s {
        case .playing:   return "playing"
        case .paused:    return "paused"
        case .buffering: return "loading"
        case .stopped:   return "stopped"
        case .idle:      return "idle (no content)"
        }
    }

    private func fmtClock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func refreshDiagnostic() async {
        diagLoading = true
        async let media = roku.rawMediaPlayer()
        async let active = roku.rawActiveApp()
        async let parsed = roku.mediaPlayerState()
        diagMedia = (await media) ?? "(unreachable)"
        diagActiveApp = (await active) ?? "(unreachable)"
        diagMediaParsed = await parsed
        diagLoading = false
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Where to find the address")
            VStack(alignment: .leading, spacing: 6) {
                stepLine("On the Roku remote, press Home.")
                stepLine("Open Settings → Network → About.")
                stepLine("Read the line that says \u{201C}IP address\u{201D} — type those numbers here.")
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .font(HearthFont.sans(size: 18, weight: .bold))
                .foregroundStyle(HearthColor.inkSoft)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(HearthFont.sans(size: 22, weight: .bold))
            .foregroundStyle(HearthColor.ink)
    }

    private func stepLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(HearthColor.ember).frame(width: 6, height: 6).padding(.top, 9)
            Text(text)
                .font(HearthFont.sans(size: 18))
                .foregroundStyle(HearthColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() async {
        testing = true
        lastResult = .none
        let ok = await roku.setHost(ip)
        lastResult = ok ? .success : .failure
        testing = false
        if ok {
            loadingApps = true
            let apps = await roku.installedApps() ?? []
            installedApps = apps
            loadingApps = false
        }
    }
}

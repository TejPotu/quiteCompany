import SwiftUI
import LiteRTLMSwift

// Onboarding sheet for the on-device companion. Triggered from a discreet
// button on HomeScreen (developer-facing — the user enables once on the dad's
// iPad and then it never reappears).
struct GemmaSetupSheet: View {
    @Environment(HearthGemma.self) private var gemma
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            statusCard
            Spacer()
            footer
        }
        .padding(36)
        .background(HearthColor.paper.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "On-device companion")
            Text("Let Hearth speak for itself.")
                .font(HearthFont.serif(size: 40, weight: .medium))
                .tracking(-0.6)
                .foregroundStyle(HearthColor.ink)
            Text("Download the Gemma 4 model once (about 2.6 GB). After that, "
                 + "Hearth writes its own warm, time-aware greetings right on the iPad — "
                 + "no internet, no servers.")
                .font(HearthFont.sans(size: 20))
                .foregroundStyle(HearthColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch gemma.status {
            case .idle:
                idleView
            case .downloading(let p):
                downloadingView(progress: p)
            case .loadingEngine:
                loadingView
            case .ready:
                readyView
            case .error(let msg):
                errorView(message: msg)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28).fill(HearthColor.cardWarm))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(HearthColor.borderSoft, lineWidth: 1))
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("Ready to download")
            Text("Best on Wi-Fi. Once finished, the model stays on this iPad.")
                .font(HearthFont.sans(size: 18))
                .foregroundStyle(HearthColor.inkSoft)
            HearthButton("Download companion", kind: .primary, icon: "download-simple") {
                Task { await gemma.startDownload() }
            }
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            label("Downloading — \(Int(progress * 100))%")
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(HearthColor.ember)
            Text("\(gemma.downloader.downloadedBytesDisplay) of \(gemma.downloader.totalBytesDisplay)")
                .font(HearthFont.sans(size: 16).monospacedDigit())
                .foregroundStyle(HearthColor.inkMute)
            HearthButton("Pause", kind: .secondary) {
                gemma.pauseDownload()
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.regular).tint(HearthColor.ember)
            VStack(alignment: .leading, spacing: 4) {
                label("Waking the companion")
                Text("This takes a few seconds the first time.")
                    .font(HearthFont.sans(size: 17))
                    .foregroundStyle(HearthColor.inkSoft)
            }
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(name: "check-circle", size: 28, color: HearthColor.sageDeep)
                label("Companion is ready")
            }
            Text("Hearth will start writing its own greetings on the Home screen.")
                .font(HearthFont.sans(size: 18))
                .foregroundStyle(HearthColor.inkSoft)
            HearthButton("Done", kind: .primary) { dismiss() }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(name: "x-circle", size: 28, color: HearthColor.ember)
                label("Something went wrong")
            }
            Text(message)
                .font(HearthFont.sans(size: 17))
                .foregroundStyle(HearthColor.inkSoft)
            HearthButton("Try again", kind: .primary, icon: "arrow-clockwise") {
                Task { await gemma.startDownload() }
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
}

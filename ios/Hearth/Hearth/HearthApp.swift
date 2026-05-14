import SwiftUI

@main
struct HearthApp: App {
    @State private var gemma = HearthGemma()
    @State private var roku = RokuController()
    @State private var cues = CueStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gemma)
                .environment(roku)
                .environment(cues)
                .task { await gemma.prepareIfNeeded() }
        }
    }
}

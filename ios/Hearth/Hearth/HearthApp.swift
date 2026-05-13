import SwiftUI

@main
struct HearthApp: App {
    @State private var gemma = HearthGemma()
    @State private var roku = RokuController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gemma)
                .environment(roku)
                .task { await gemma.prepareIfNeeded() }
        }
    }
}

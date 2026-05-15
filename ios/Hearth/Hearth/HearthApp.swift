import SwiftUI

@main
struct HearthApp: App {
    @State private var gemma = HearthGemma()
    @State private var roku = RokuController()
    @State private var cues = CueStore()
    @State private var people = PeopleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gemma)
                .environment(roku)
                .environment(cues)
                .environment(people)
                .task { await gemma.prepareIfNeeded() }
        }
    }
}

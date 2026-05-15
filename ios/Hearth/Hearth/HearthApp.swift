import SwiftUI

@main
struct HearthApp: App {
    @State private var gemma = HearthGemma()
    @State private var roku = RokuController()
    @State private var cues = CueStore()
    @State private var people = PeopleStore()
    @State private var presence = PresenceMonitor()
    @State private var alerter = CaregiverAlerter()
    @State private var tts = HearthTTS()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gemma)
                .environment(roku)
                .environment(cues)
                .environment(people)
                .environment(presence)
                .environment(alerter)
                .environment(tts)
                .task { await gemma.prepareIfNeeded() }
        }
    }
}

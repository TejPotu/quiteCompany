import SwiftUI

// Streaming app on the Roku. `rokuAppId` is the channel ID Roku assigns to the
// app — these are stable per app, but if a show *moves* between apps the
// mapping below needs to be updated. To list what's actually installed on the
// connected Roku: GET http://<roku-ip>:8060/query/apps.
struct StreamingPlatform: Equatable, Hashable {
    let name: String
    let shortName: String
    let rokuAppId: Int
}

enum Platforms {
    static let netflix     = StreamingPlatform(name: "Netflix",     shortName: "Netflix",  rokuAppId: 12)
    static let max         = StreamingPlatform(name: "Max",         shortName: "Max",      rokuAppId: 61322)
    static let hulu        = StreamingPlatform(name: "Hulu",        shortName: "Hulu",     rokuAppId: 2285)
    static let disneyPlus  = StreamingPlatform(name: "Disney+",     shortName: "Disney+",  rokuAppId: 291097)
    static let primeVideo  = StreamingPlatform(name: "Prime Video", shortName: "Prime",    rokuAppId: 13)
    static let peacock     = StreamingPlatform(name: "Peacock",     shortName: "Peacock",  rokuAppId: 593099)
    static let paramount   = StreamingPlatform(name: "Paramount+",  shortName: "Paramount+", rokuAppId: 31440)
    static let appleTV     = StreamingPlatform(name: "Apple TV+",   shortName: "Apple TV+",  rokuAppId: 551012)
}

struct Show: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let episode: String
    let resume: String
    let imageName: String

    // Roku launch metadata.
    //   • platform: which streaming app holds the show.
    //   • contentId: the app's internal title ID. For Netflix it's the number
    //     in netflix.com/title/<N>. With it set, we deep-link straight to the
    //     title page where Resume is one click. Without it, we just open the
    //     app's home screen.
    //   • mediaType: "series" (default, lands on title page) or "episode"
    //     (auto-plays a specific episode if the contentId is that episode).
    //   • rokuKeyword: overrides title for the global-search fallback path
    //     (useful for punctuation Roku doesn't like, e.g. M*A*S*H → "MASH").
    var platform: StreamingPlatform? = nil
    var contentId: String? = nil
    var mediaType: String? = nil
    var rokuKeyword: String? = nil

    static func == (lhs: Show, rhs: Show) -> Bool { lhs.title == rhs.title }
}

enum FavouritesData {
    // Posters and order sourced from "TV List for Dad.pptx".
    // Platform assignments are best-guess US availability as of May 2026. If a
    // show opens the wrong app, change `platform:` below. Common reshuffles:
    // Friends/Office bounce between Max/Peacock; Yellowstone is on Peacock
    // *and* Paramount+.
    static let all: [Show] = [
        Show(title: "Seinfeld",
             episode: "Episode 14 — The Soup Nazi",
             resume: "8 minutes in",
             imageName: "Seinfeld",
             platform: Platforms.netflix),
        Show(title: "Grey's Anatomy",
             episode: "Episode 3 — A hard day at Grey Sloan",
             resume: "15 minutes in",
             imageName: "GreysAnatomy",
             platform: Platforms.netflix),
        Show(title: "Big Bang Theory",
             episode: "Episode 9 — The Bath Item Gift Hypothesis",
             resume: "Start of episode",
             imageName: "BigBangTheory",
             platform: Platforms.max),
        Show(title: "Young Sheldon",
             episode: "Episode 1 — Pilot",
             resume: "Start of episode",
             imageName: "YoungSheldon",
             platform: Platforms.netflix,
             contentId: "80192612"),  // netflix.com/title/80192612 (jbv=)
        Show(title: "Curb Your Enthusiasm",
             episode: "Episode 4 — The Smoking Jacket",
             resume: "22 minutes in",
             imageName: "CurbYourEnthusiasm",
             platform: Platforms.max),
        Show(title: "Veep",
             episode: "Episode 2 — Frozen Yoghurt",
             resume: "Start of episode",
             imageName: "Veep",
             platform: Platforms.max),
        Show(title: "Friends",
             episode: "Episode 12 — The One with the Embryos",
             resume: "11 minutes in",
             imageName: "Friends",
             platform: Platforms.max),
        Show(title: "The West Wing",
             episode: "Episode 6 — A Proportional Response",
             resume: "Start of episode",
             imageName: "TheWestWing",
             platform: Platforms.max),
        Show(title: "Grace and Frankie",
             episode: "Episode 3 — The Dinner",
             resume: "5 minutes in",
             imageName: "GraceAndFrankie",
             platform: Platforms.netflix),
        Show(title: "Poldark",
             episode: "Episode 1 — A new beginning",
             resume: "18 minutes in",
             imageName: "Poldark",
             platform: Platforms.netflix),
        Show(title: "Modern Family",
             episode: "Episode 7 — En Garde",
             resume: "Start of episode",
             imageName: "ModernFamily",
             platform: Platforms.peacock),
        Show(title: "Frasier",
             episode: "Episode 4 — I Hate Frasier Crane",
             resume: "9 minutes in",
             imageName: "Frasier",
             platform: Platforms.paramount),
        Show(title: "Cheers",
             episode: "Episode 22 — Showdown",
             resume: "Start of episode",
             imageName: "Cheers",
             platform: Platforms.paramount),
        Show(title: "M*A*S*H",
             episode: "Episode 12 — Sometimes You Hear the Bullet",
             resume: "14 minutes in",
             imageName: "MASH",
             platform: Platforms.hulu,
             rokuKeyword: "MASH"),
        Show(title: "The Office",
             episode: "Episode 6 — Diversity Day",
             resume: "Start of episode",
             imageName: "TheOffice",
             platform: Platforms.peacock),
        Show(title: "Parks and Recreation",
             episode: "Episode 3 — The Reporter",
             resume: "26 minutes in",
             imageName: "ParksAndRecreation",
             platform: Platforms.peacock),
        Show(title: "Yellowstone",
             episode: "Episode 1 — Daybreak",
             resume: "Start of episode",
             imageName: "Yellowstone",
             platform: Platforms.peacock),
        Show(title: "CBS Evening News",
             episode: "Tonight's broadcast",
             resume: "7 minutes in",
             imageName: "CBSEveningNews",
             platform: Platforms.paramount),
        Show(title: "Downton Abbey",
             episode: "Episode 4 — A new arrival",
             resume: "Start of episode",
             imageName: "DowntonAbbey",
             platform: Platforms.peacock),
    ]
}

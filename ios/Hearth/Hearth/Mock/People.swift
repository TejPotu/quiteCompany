import SwiftUI

struct Person {
    let name: String
    let relationship: String
    let from: String
    let age: Int
    let portraitTone: PhotoTone
}

struct MemoryPhoto: Identifiable {
    let id = UUID()
    let caption: String
    let tone: PhotoTone
}

enum PeopleData {
    static let sarah = Person(
        name: "Sarah",
        relationship: "Your daughter",
        from: "Brighton",
        age: 52,
        portraitTone: .ember
    )

    static let photos: [MemoryPhoto] = [
        MemoryPhoto(caption: "The beach, last summer", tone: .sky),
        MemoryPhoto(caption: "Christmas 2024",         tone: .ember),
        MemoryPhoto(caption: "Sarah's wedding, 2010",  tone: .honey),
        MemoryPhoto(caption: "Garden, spring",         tone: .sage),
        MemoryPhoto(caption: "Tea together",           tone: .honey),
        MemoryPhoto(caption: "Walk by the sea",        tone: .sky),
    ]
}

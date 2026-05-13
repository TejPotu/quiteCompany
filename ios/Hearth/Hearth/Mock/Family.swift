import Foundation

struct FamilyContact: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let relation: String
    let initial: String
    let tone: PhotoTone
}

enum FamilyData {
    static let all: [FamilyContact] = [
        FamilyContact(name: "Sarah",    relation: "your daughter", initial: "S", tone: .ember),
        FamilyContact(name: "Tom",      relation: "your son",      initial: "T", tone: .sage),
        FamilyContact(name: "Margaret", relation: "your wife",     initial: "M", tone: .sky),
        FamilyContact(name: "Henry",    relation: "your brother",  initial: "H", tone: .honey),
    ]
}

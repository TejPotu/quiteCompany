import Foundation
import UIKit
import Observation

// Caregiver-indexed people. The patient never types here — they only see a
// match result. The caregiver writes once: photo + name + relationship + a
// short note. The photo's face fingerprint is cached on the entry so the
// People tab can match a fresh camera capture in milliseconds without
// re-running Vision on every indexed photo.
@Observable @MainActor
final class PeopleStore {
    var entries: [PersonEntry]

    init(initial: [PersonEntry] = []) {
        self.entries = initial
    }

    func upsert(_ entry: PersonEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}

struct PersonEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var relationship: String       // "Daughter", "Brother", "Neighbour Helen"
    var from: String?              // "Brighton"
    var birthday: Date?
    var notes: String?             // free text — e.g. "Calls every Sunday"
    var photoData: Data?           // JPEG/PNG bytes — fed to Gemma at verify time
    var featurePrintData: Data?    // serialized VNFeaturePrintObservation — fast retrieval

    static let blank = PersonEntry(
        name: "",
        relationship: "",
        from: nil,
        birthday: nil,
        notes: nil,
        photoData: nil,
        featurePrintData: nil
    )
}

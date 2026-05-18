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
    var isSeeding: Bool = false

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

    // Demo seed — pulls a small set of well-known faces from Wikipedia and
    // computes their feature prints up front. Gemma isn't needed at index
    // time in this pipeline: it only runs at match time to verify a
    // shortlist. Idempotent — bails if any entries already exist.
    func seedFamousPeopleIfEmpty() async {
        guard entries.isEmpty, !isSeeding else { return }
        isSeeding = true
        defer { isSeeding = false }

        for spec in Self.demoSpecs {
            guard let url = await fetchThumbnailURL(forWikiTitle: spec.wikiTitle),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.85),
                  let fingerprint = await FaceMatcher.computeFingerprint(for: image)
            else { continue }

            let entry = PersonEntry(
                name: spec.name,
                relationship: spec.relationship,
                from: spec.from,
                birthday: nil,
                notes: spec.notes,
                photoData: jpeg,
                featurePrintData: fingerprint
            )
            entries.append(entry)
        }
    }

    private func fetchThumbnailURL(forWikiTitle title: String) async -> URL? {
        let slug = title.replacingOccurrences(of: " ", with: "_")
        guard let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)") else {
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: api),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Prefer the larger originalimage so the face is detectable; fall back
        // to thumbnail. Both come from upload.wikimedia.org.
        let candidate =
            (json["originalimage"] as? [String: Any])?["source"] as? String
            ?? (json["thumbnail"] as? [String: Any])?["source"] as? String
        return candidate.flatMap { URL(string: $0) }
    }

    private struct DemoSpec {
        let name: String
        let relationship: String
        let from: String?
        let notes: String?
        let wikiTitle: String
    }

    // Hand-picked, varied set so face matching is visibly working across
    // different looks. Notes are written in the same voice the caregiver
    // would use — context the patient might want reminding of.
    private static let demoSpecs: [DemoSpec] = [
        DemoSpec(
            name: "Tom Hanks",
            relationship: "Famous actor",
            from: "Hollywood",
            notes: "You loved him in Forrest Gump and Cast Away.",
            wikiTitle: "Tom Hanks"
        ),
        DemoSpec(
            name: "Morgan Freeman",
            relationship: "Famous actor",
            from: "Hollywood",
            notes: "The narrator from The Shawshank Redemption.",
            wikiTitle: "Morgan Freeman"
        ),
        DemoSpec(
            name: "Scarlett Johansson",
            relationship: "Famous actress",
            from: "Hollywood",
            notes: "Black Widow in the Marvel films.",
            wikiTitle: "Scarlett Johansson"
        ),
        DemoSpec(
            name: "Denzel Washington",
            relationship: "Famous actor",
            from: "Hollywood",
            notes: "Won Oscars for Training Day and Glory.",
            wikiTitle: "Denzel Washington"
        ),
        DemoSpec(
            name: "Jennifer Lawrence",
            relationship: "Famous actress",
            from: "Hollywood",
            notes: "Katniss in The Hunger Games.",
            wikiTitle: "Jennifer Lawrence"
        ),
        DemoSpec(
            name: "Brad Pitt",
            relationship: "Famous actor",
            from: "Hollywood",
            notes: "From Ocean's Eleven and Once Upon a Time in Hollywood.",
            wikiTitle: "Brad Pitt"
        )
    ]
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

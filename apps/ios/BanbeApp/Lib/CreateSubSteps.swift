import Foundation

/// Note 69: Basics and Tickets had too many fields on one screen, so each is split into parts with their own small
/// numbered bar (nested under the main step bar, styled differently). One part is on screen at a time; Back / Next move
/// between parts first, then between steps. "Take me to this field" (Fix, Still needed, Review with gaps) opens the
/// part that holds the field. Web twin: src/lib/createSubSteps.js.
enum CreateSubSteps {
    struct Part: Equatable {
        let id: String
        let vi: String
        let en: String
        /// Field ids shown in this part (the ids of CreateFieldGuide / CreateProgress).
        let fields: [String]
    }

    /// Step indexes (CreateEventView.Section raw values).
    static let basicsStep = 1
    static let ticketsStep = 3

    static let basics: [Part] = [
        Part(id: "name", vi: "Tên", en: "Name", fields: ["name"]),
        Part(id: "story", vi: "Mô tả", en: "Story", fields: ["description", "intro"]),
        Part(id: "greeting", vi: "Lời chào", en: "Greeting", fields: ["greeting"]),
        Part(id: "categories", vi: "Hạng mục", en: "Categories", fields: ["categories", "keywords"]),
        // "Included" and every event-type fact (whichever types are picked).
        Part(id: "details", vi: "Chi tiết", en: "Details", fields: ["included"]),
    ]

    static let tickets: [Part] = [
        Part(id: "price", vi: "Giá", en: "Price", fields: ["price"]),
        Part(id: "seats", vi: "Số chỗ", en: "Seats", fields: ["seats"]),
        Part(id: "privacy", vi: "Quyền riêng tư", en: "Privacy", fields: ["visibility"]),
        Part(id: "criteria", vi: "Ai được đặt", en: "Who can book", fields: ["criteria"]),
    ]

    /// The parts of a step; empty for steps that stay on one screen (Host, When & where, Photos).
    static func parts(step: Int) -> [Part] {
        switch step {
        case basicsStep: return basics
        case ticketsStep: return tickets
        default: return []
        }
    }

    /// The part that shows a field. Event-type facts (dietary, lineup, alcohol…) live in Basics › Details.
    static func index(of field: String, step: Int) -> Int? {
        let list = parts(step: step)
        guard !list.isEmpty else { return nil }
        if let i = list.firstIndex(where: { $0.fields.contains(field) }) { return i }
        if step == basicsStep, CreateFieldGuide.step(of: field) == basicsStep { return list.count - 1 }
        return nil
    }

    /// Done = nothing required is missing in the part, and the host has seen it (a part with no required field is
    /// "done" once visited, so the ✓ never claims work the host has not looked at).
    static func done(step: Int, missing: [String], visited: Set<Int>) -> [Bool] {
        parts(step: step).indices.map { i in
            let holds = missing.contains { index(of: $0, step: step) == i }
            return !holds && visited.contains(i)
        }
    }
}

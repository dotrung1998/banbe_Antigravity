import Foundation

/// Create event: "take me to the field" (note 53). A recipe Fix, or Review with gaps, lands on the exact field —
/// scrolled to the middle, glowing, and focused when it takes typing — not just on its step. The ids match
/// `fix.field` in Lib/EventRecipe.swift and the `create.field.<id>` anchors in CreateEventView.
/// Web twin: src/lib/createFieldGuide.js (same ids, same order; tests mirrored).
enum CreateFieldGuide {
    /// Field id -> step index (0 Host, 1 Basics, 2 When & where, 3 Tickets, 4 Photos).
    static let fieldStep: [String: Int] = [
        "hostName": 0,
        "name": 1, "description": 1, "intro": 1, "greeting": 1, "categories": 1, "keywords": 1, "included": 1,
        "location": 2, "date": 2,
        "price": 3, "seats": 3,
        "photos": 4,
    ]

    /// Fields that take typing, so a jump there also focuses them and opens the keyboard.
    static let textFields: Set<String> = ["hostName", "name", "description", "intro", "greeting", "keywords", "location", "price"]

    static func step(of field: String) -> Int? { fieldStep[field] }
    static func isTextField(_ field: String) -> Bool { textFields.contains(field) }

    /// The first required field still missing, in the order the steps show them.
    static func firstMissing(_ missing: [String: Bool]) -> String? {
        let order = ["hostName", "name", "description", "categories", "included", "location", "date", "seats", "photos"]
        return order.first { missing[$0] == true }
    }

    /// The scroll anchor of a field (or of one of its sub-fields, e.g. "greetingEn").
    static func anchor(_ field: String) -> String { "create.field.\(field)" }
}

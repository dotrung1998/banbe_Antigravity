import Foundation

/// Create event: ONE calculation behind the progress ring, "N steps left", "Still needed here" and the Review
/// summary. Before this, each was its own hand-kept list and they drifted (iOS never asked for a valid price).
/// `required` is the active event type's list, so a type can add or drop required fields without the ring,
/// the count and the footer disagreeing.
/// Web twin: src/lib/createProgress.js. Shared vectors: tests/fixtures/create-progress.json.
enum CreateProgress {
    static let stepCount = 5

    /// Every field that can be required, in the order the steps show them.
    static let fieldOrder = ["hostName", "name", "description", "categories", "included", "location", "date", "price", "seats", "photos"]

    struct Step: Equatable {
        let index: Int
        let done: Bool
        let missing: [String]
    }

    struct Result: Equatable {
        let steps: [Step]
        let doneCount: Int
        let percent: Int
        let stepsLeft: Int
        let missing: [String]
        var firstMissing: String? { missing.first }
    }

    /// `missing[id] == true` while that field is still missing. Only fields in `required` count.
    static func compute(missing: [String: Bool], required: [String] = fieldOrder) -> Result {
        let req = Set(required)
        let gaps = fieldOrder.filter { req.contains($0) && missing[$0] == true }
        let steps = (0..<stepCount).map { index in
            let stepMissing = gaps.filter { CreateFieldGuide.step(of: $0) == index }
            return Step(index: index, done: stepMissing.isEmpty, missing: stepMissing)
        }
        let done = steps.filter(\.done).count
        return Result(steps: steps, doneCount: done,
                      percent: Int((Double(done) / Double(stepCount) * 100).rounded()),
                      stepsLeft: stepCount - done, missing: gaps)
    }

    /// The short label for a missing field, as shown after "Still needed: ".
    static func label(_ id: String, minPhotos: Int, T: (String, String) -> String) -> String {
        switch id {
        case "hostName": return T("tên host", "host name")
        case "name": return T("tên sự kiện", "event name")
        case "description": return T("mô tả", "description")
        case "categories": return T("danh mục", "a category")
        case "included": return T("mục bao gồm", "an included item")
        case "location": return T("địa chỉ gợi ý", "a suggested address")
        case "date": return T("ngày & giờ", "date & time")
        case "price": return T("giá vé hợp lệ", "a valid price")
        case "seats": return T("số chỗ", "seats")
        case "photos": return T("ít nhất \(minPhotos) ảnh", "at least \(minPhotos) photos")
        default: return id
        }
    }
}

import Foundation

/// Mirrors the `notifications` table (migration 019). `data` is a free-form
/// jsonb payload — decoded here as [String: AnyCodableValue] since its shape
/// depends on `kind` (e.g. 'new_message' carries thread_id/event_id,
/// 'booking_cancelled' carries booking_id/reason/had_payment).
struct AppNotification: Codable, Identifiable, Hashable {
    let id: UUID
    var recipientId: UUID
    var kind: String
    var title: String
    var body: String
    var data: [String: AnyCodableValue]
    var readAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipientId = "recipient_id"
        case kind
        case title
        case body
        case data
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

/// Minimal type-erased JSON value, just enough to decode an arbitrary jsonb
/// column without a full custom decoder for each notification `kind`.
enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

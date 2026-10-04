import Foundation

/// Storage constants for the temporary dispute chat's attachments
/// (migration 131).
///
/// The ordinary chat's `chat-attachments` bucket is keyed by CONVERSATION
/// thread id; these are keyed by DISPUTE thread id, which is what lets the
/// bucket's policies grant access to exactly the two parties of one dispute
/// and lets the purge sweep delete a transcript's files without ever touching
/// an ordinary chat's. Kept as named constants rather than string literals so
/// the bucket can't drift between the upload, the signing and the cleanup.
enum DisputeAttachments {
    static let bucket = "dispute-attachments"
}

/// One line in the temporary dispute chat (`dispute_messages`) — the Swift
/// counterpart of GocContext.jsx's disputeChatMessages. Purged along with
/// its thread once resolve_dispute() closes it out and the grace window in
/// purge_resolved_dispute_threads() elapses.
///
/// The attachment fields (migration 131) mirror the ordinary chat's
/// `messages` columns exactly — same names, same meaning, same optionality —
/// so one renderer draws both. `attachmentPath` is an object path in the
/// PRIVATE `dispute-attachments` bucket, addressed by DISPUTE THREAD id (not
/// conversation thread id): it is readable only by that dispute's two parties
/// while the dispute is readable, and it is deleted with the transcript.
struct DisputeMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var senderId: UUID?
    var senderRole: String  // "guest" | "organizer" | "system"
    var body: String
    var createdAt: Date
    var attachmentPath: String?
    var attachmentType: String?
    var attachmentWidth: Int?
    var attachmentHeight: Int?

    var hasAttachment: Bool { !(attachmentPath ?? "").isEmpty }
    var isImageAttachment: Bool { attachmentType?.hasPrefix("image/") == true }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case senderRole = "sender_role"
        case body
        case createdAt = "created_at"
        case attachmentPath = "attachment_path"
        case attachmentType = "attachment_type"
        case attachmentWidth = "attachment_width"
        case attachmentHeight = "attachment_height"
    }
}

/// A row from `v_disputes` — RLS-scoped the same way bookings always are,
/// so the exact same query returns different things depending on who asks:
/// an organizer sees only their own events' disputes (used by
/// VerificationsView, so they can keep talking with a guest after
/// escalating — the booking leaves v_pending_verifications the moment it's
/// escalated, so without this there'd be nowhere left on that screen to
/// reach it), and a platform admin sees every dispute (used by
/// AdminDashboardView, the actual resolution desk).
struct DisputeRow: Codable, Identifiable, Hashable {
    let bookingId: UUID
    var eventName: String?
    var guestName: String?
    var organizerName: String?
    var totalVnd: Int
    var paymentRef: String?
    var transactionId: String?
    var proofPath: String?
    var disputeReason: String?
    var disputeResolvedAt: Date?
    var disputeResolution: String?
    var id: UUID { bookingId }

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case eventName = "event_name"
        case guestName = "guest_name"
        case organizerName = "organizer_name"
        case totalVnd = "total_vnd"
        case paymentRef = "payment_ref"
        case transactionId = "transaction_id"
        case proofPath = "proof_path"
        case disputeReason = "dispute_reason"
        case disputeResolvedAt = "dispute_resolved_at"
        case disputeResolution = "dispute_resolution"
    }
}

/// One line of `payment_audit_log` — the T1/T2/T3 trail a dispute is argued
/// on, same data AdminDashboardView shows Disputes.jsx showing on web.
struct PaymentAuditEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var action: String
    var at: Date
    var actorKind: String?
    var ip: String?

    enum CodingKeys: String, CodingKey {
        case id, action, at
        case actorKind = "actor_kind"
        case ip
    }
}

/// One row of get_my_dispute_chats() (migration 129) — the yellow "dispute"
/// section pinned at the top of Messages. One per live dispute chat this
/// account is a party to, whether it's a payment dispute (the host escalated
/// to banbe) or a refund dispute (the goer reported not receiving the money,
/// which had no chat at all before this).
///
/// `bookingId` is nil and `refundClaimId` set for a refund dispute, exactly as
/// the row is keyed server-side; `kind` says which, so a view never has to
/// infer it. `resolvedAt`/`purgeAfter` drive the "ends in N days" countdown —
/// both parties keep the row for a 7-day window after a REFUND dispute
/// settles, then the purge sweep removes it for good.
struct DisputeChatSummary: Codable, Identifiable, Hashable {
    let threadId: UUID
    /// "payment" | "refund"
    let kind: String
    let bookingId: UUID?
    let refundClaimId: UUID?
    let eventId: String?
    let eventKey: String?
    let eventName: String?
    /// Whoever this account is NOT — the organizer for a goer, the guest for
    /// a host.
    let otherName: String?
    let otherAvatarUrl: String?
    let amountVnd: Int?
    /// refund_claims.status while this is a refund dispute (nil otherwise).
    let claimStatus: String?
    let disputedAt: Date?
    let resolvedAt: Date?
    let purgeAfter: Date?
    let lastMessageAt: Date?
    let lastMessageBody: String?
    let messageCount: Int
    /// "guest" | "organizer" — which side of this dispute this account is on.
    let viewerRole: String
    /// The refund claim's UNDERLYING booking — migration 130. Distinct from
    /// `bookingId` above, which is the dispute THREAD's own booking_id and is
    /// therefore nil for a refund dispute (a thread can only be keyed by one
    /// or the other). This is the id a client navigates by.
    var sourceBookingId: UUID?
    /// The EXISTING (event_id, guest_id) conversation this dispute renders
    /// inside, so both parties open the booking conversation they already
    /// have rather than ending up with a second one.
    var conversationThreadId: UUID?
    /// Set by close_refund_dispute() — drives "Dispute completed" and clears
    /// the active-dispute indicator on both sides.
    var disputeClosedAt: Date?
    var disputeClosedByRole: String?
    var id: UUID { threadId }
    var isRefund: Bool { kind == "refund" }
    var isConcluded: Bool { resolvedAt != nil }
    /// Still being argued: not closed by a party AND the claim is still in
    /// its 'disputed' state. This, not `isConcluded`, is what highlights the
    /// Inbox row — a dispute can conclude without either party closing it.
    var isActiveDispute: Bool {
        isRefund && disputeClosedAt == nil && claimStatus == "disputed"
    }

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case kind
        case bookingId = "booking_id"
        case refundClaimId = "refund_claim_id"
        case eventId = "event_id"
        case eventKey = "event_key"
        case eventName = "event_name"
        case otherName = "other_name"
        case otherAvatarUrl = "other_avatar_url"
        case amountVnd = "amount_vnd"
        case claimStatus = "claim_status"
        case disputedAt = "disputed_at"
        case resolvedAt = "resolved_at"
        case purgeAfter = "purge_after"
        case lastMessageAt = "last_message_at"
        case lastMessageBody = "last_message_body"
        case messageCount = "message_count"
        case viewerRole = "viewer_role"
        case sourceBookingId = "source_booking_id"
        case conversationThreadId = "conversation_thread_id"
        case disputeClosedAt = "dispute_closed_at"
        case disputeClosedByRole = "dispute_closed_by_role"
    }
}

/// The VERIFIED, per-claim answer to "is there a refund dispute chat for this
/// claim, who am I in it, and is it still open" —
/// get_refund_dispute_thread() (migration 130).
///
/// Both refund entry points (the host's Awaiting Verification queue and the
/// goer's refund card) read THIS rather than looking their claim up in the
/// get_my_dispute_chats() list, because that list is a cached, poll-driven
/// snapshot: on a screen reached before any Inbox load, or right after the
/// dispute was raised on the other device, it can be empty or stale, and the
/// old code read `viewerRole` straight off it to decide who the chat was
/// "with". Resolving by exact claim id server-side is what makes both the
/// label and the authorization verifiable rather than guessed.
struct RefundDisputeThread: Codable, Hashable {
    let found: Bool
    let disputeThreadId: UUID?
    let refundClaimId: UUID?
    let bookingId: UUID?
    let conversationThreadId: UUID?
    let eventId: String?
    let eventName: String?
    let organizerName: String?
    let amountVnd: Int?
    let claimStatus: String?
    let claimReason: String?
    let disputedAt: Date?
    let hostResponseDueAt: Date?
    let disputeClosedAt: Date?
    let disputeClosedByRole: String?
    let resolvedAt: Date?
    let purgeAfter: Date?
    let resolutionKind: String?
    let resolutionNote: String?
    let messageCount: Int?
    /// "guest" | "organizer" | "admin" — resolved server-side from the
    /// caller's own position on the claim, never inferred client-side.
    let viewerRole: String?
    let otherName: String?
    /// Server-supplied reason code when this account isn't a party.
    let error: String?
    /// Why `found` is false: "not_disputed", or "deleted_by_you" once the goer
    /// removed their own copy (migration 134).
    var reason: String?
    /// A refund dispute only while its claim is still 'disputed' and neither
    /// party has pressed close.
    var isActive: Bool { found && resolvedAt == nil && disputeClosedAt == nil }
    /// Closed for reading, still inside the 7-day retention window.
    var isCompleted: Bool { found && (resolvedAt != nil || disputeClosedAt != nil) }
    var canDownload: Bool { found }
    /// The refund has gone through the normal flow (host marked it sent, goer
    /// confirmed it was received, or it was waived). Only then may the dispute
    /// be closed (migration 135).
    var refundSettled: Bool { claimStatus == "guest_confirmed" || claimStatus == "waived" }

    enum CodingKeys: String, CodingKey {
        case found
        case disputeThreadId = "dispute_thread_id"
        case refundClaimId = "refund_claim_id"
        case bookingId = "booking_id"
        case conversationThreadId = "conversation_thread_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case organizerName = "organizer_name"
        case amountVnd = "amount_vnd"
        case claimStatus = "claim_status"
        case claimReason = "claim_reason"
        case disputedAt = "disputed_at"
        case hostResponseDueAt = "host_response_due_at"
        case disputeClosedAt = "dispute_closed_at"
        case disputeClosedByRole = "dispute_closed_by_role"
        case resolvedAt = "resolved_at"
        case purgeAfter = "purge_after"
        case resolutionKind = "resolution_kind"
        case resolutionNote = "resolution_note"
        case messageCount = "message_count"
        case viewerRole = "viewer_role"
        case otherName = "other_name"
        case error
        case reason
    }
}

/// Pure, testable selection of WHICH system message a dispute attaches to.
///
/// Extracted from ChatView's own `disputeCardMessageIDs` (MessagingViews.swift)
/// so the rule can be unit-tested without a view or a network — see
/// BanbeAppTests/ConversationDisputeAttachmentTests.swift.
///
/// Why this exists at all: `messages` rows carry no booking or claim id (the
/// table is (thread_id, sender_id, body, kind, …), and every cancellation RPC
/// writes the same prose prefix), so there is no per-message booking identity
/// to match on. Matching "every card whose body starts with Booking cancelled."
/// is precisely what mounted N copies of ONE dispute, each polling the shared
/// global transcript state and blanking the others. The selection is therefore
/// deterministic and documented rather than absent:
///
///   refund  → the LAST cancellation card at or before the claim's own
///             `disputed_at` (a refund dispute is always raised after the
///             cancellation that caused it), else the last card overall.
///   payment → the FIRST "Payment confirmed" card (a payment dispute can only
///             exist after a payment was confirmed on that booking).
enum DisputeCardAttachment {
    /// The minimum a system message needs for this decision — deliberately not
    /// the whole `ChatMessage`, so the rule stays independent of every other
    /// column that struct carries.
    struct SystemMessage: Equatable {
        let id: UUID
        let body: String
        let createdAt: Date
    }

    /// Body prefixes each lifecycle RPC writes today (060 confirm_payment,
    /// 059 reject_pending_guest, 022/069 cancel_booking). Mirrors
    /// ChatView.classifySystemMessage's classification, extracted here so this
    /// type doesn't depend on a SwiftUI view.
    enum CardKind: Equatable {
        case confirmed   // "Payment confirmed"
        case declined    // "Booking cancelled"
    }

    static func classify(_ body: String) -> CardKind? {
        if body.hasPrefix("Host marked payment received via") { return .confirmed }
        if body.hasPrefix("Người tổ chức không nhận yêu cầu đặt chỗ này")
            || body.hasPrefix("Booking cancelled.") { return .declined }
        return nil
    }

    /// Oldest first, with the message id as a tiebreaker so the same set of
    /// cards always sorts the same way regardless of loader order.
    private static func oldestFirst(_ cards: [SystemMessage]) -> [SystemMessage] {
        cards.sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    private static func cards(of kind: CardKind, in messages: [SystemMessage]) -> [SystemMessage] {
        oldestFirst(messages.filter { classify($0.body) == kind })
    }

    /// The ONE cancellation card a refund dispute belongs to, or nil when the
    /// conversation has no cancellation card at all.
    static func refundCardMessageID(in messages: [SystemMessage], disputedAt: Date?) -> UUID? {
        let declined = cards(of: .declined, in: messages)
        guard !declined.isEmpty else { return nil }
        if let disputedAt {
            return declined.last(where: { $0.createdAt <= disputedAt })?.id ?? declined.last?.id
        }
        return declined.last?.id
    }

    /// The ONE "Payment confirmed" card a payment dispute belongs to, or nil.
    static func paymentCardMessageID(in messages: [SystemMessage]) -> UUID? {
        cards(of: .confirmed, in: messages).first?.id
    }
}

/// One line of a downloaded refund-dispute transcript
/// (get_refund_dispute_transcript(), migration 130) — the export's own
/// message shape, deliberately separate from `DisputeMessage`: this one
/// carries the participant NAME resolved server-side, so an exported record
/// stays readable after an account is deleted.
///
/// Migration 131 adds the same four attachment fields the transcript table
/// gained. They are metadata only — the object itself is deleted with the
/// temporary chat, which is exactly why the export also carries
/// `RefundDisputeTranscript.attachmentNotice` and never a URL.
struct DisputeTranscriptMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let senderRole: String
    let senderName: String?
    let body: String
    let createdAt: Date
    var attachmentPath: String?
    var attachmentType: String?
    var attachmentWidth: Int?
    var attachmentHeight: Int?

    var hasAttachment: Bool { !(attachmentPath ?? "").isEmpty }

    enum CodingKeys: String, CodingKey {
        case id
        case senderRole = "sender_role"
        case senderName = "sender_name"
        case body
        case createdAt = "created_at"
        case attachmentPath = "attachment_path"
        case attachmentType = "attachment_type"
        case attachmentWidth = "attachment_width"
        case attachmentHeight = "attachment_height"
    }
}

/// The COMPLETE dispute record both parties can download: participants,
/// timestamps, event/booking reference, amount, claim status and every
/// message — not the visible tail of whatever happened to be loaded.
///
/// Available while the dispute is open (offered BEFORE closing, so nobody has
/// to close a dispute first to keep a copy) and for the whole 7-day window
/// after it closes.
struct RefundDisputeTranscript: Codable, Hashable {
    let found: Bool
    let disputeThreadId: UUID?
    let refundClaimId: UUID?
    let bookingId: UUID?
    let bookingCode: String?
    let conversationThreadId: UUID?
    let eventId: String?
    let eventName: String?
    let organizerLabel: String?
    let guestLabel: String?
    let amountVnd: Int?
    let claimStatus: String?
    let claimReason: String?
    let claimNote: String?
    let disputedAt: Date?
    let disputeClosedAt: Date?
    let resolvedAt: Date?
    let purgeAfter: Date?
    let messageCount: Int?
    let transcriptMessageCount: Int?
    let viewerRole: String?
    let exportedAt: Date?
    let messages: [DisputeTranscriptMessage]
    let error: String?
    /// Migration 131 — how many lines carried a file, and the server's own
    /// plain statement of what an exported attachment reference does and
    /// doesn't promise (the files are deleted with this transcript). Absent
    /// before that migration; `attachmentNotice` is nil then.
    var attachmentCount: Int?
    var attachmentNotice: String?

    enum CodingKeys: String, CodingKey {
        case found
        case disputeThreadId = "dispute_thread_id"
        case refundClaimId = "refund_claim_id"
        case bookingId = "booking_id"
        case bookingCode = "booking_code"
        case conversationThreadId = "conversation_thread_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case organizerLabel = "organizer_label"
        case guestLabel = "guest_label"
        case amountVnd = "amount_vnd"
        case claimStatus = "claim_status"
        case claimReason = "claim_reason"
        case claimNote = "claim_note"
        case disputedAt = "disputed_at"
        case disputeClosedAt = "dispute_closed_at"
        case resolvedAt = "resolved_at"
        case purgeAfter = "purge_after"
        case messageCount = "message_count"
        case transcriptMessageCount = "transcript_message_count"
        case viewerRole = "viewer_role"
        case exportedAt = "exported_at"
        case attachmentCount = "attachment_count"
        case attachmentNotice = "attachment_notice"
        case messages
        case error
    }
}

import Foundation

/// Event Project Hub (note 76): the shapes `get_event_project` and friends return (migration 210). Timestamps stay as
/// the server's ISO strings (with or without fractional seconds) and are read through `ProjectDates.parse`, so these
/// decode the same from the Supabase client and from the shared fixture tests/fixtures/project-snapshot.json.
struct ProjectSnapshot: Decodable, Equatable {
    let success: Bool
    let error: String?
    let unchanged: Bool?
    let version: Int?
    var project: ProjectInfo?
    var event: ProjectEvent?
    var isHost: Bool?
    var me: ProjectMe?
    var hosts: [ProjectPerson]?
    var members: [ProjectMember]?
    var lanes: [ProjectLane]?
    var tasks: [ProjectTask]?
    var posts: [ProjectPost]?
    var ros: [ProjectRosItem]?
    var changeRequests: [ProjectChangeRequest]?

    enum CodingKeys: String, CodingKey {
        case success, error, unchanged, version, project, event, me, hosts, members, lanes, tasks, posts, ros
        case isHost = "is_host", changeRequests = "change_requests"
    }
}

struct ProjectInfo: Decodable, Equatable {
    let eventId: String
    var channels: [ProjectChannels.Channel]
    /// "host" or "finance_alone" (215). A var: the Host's switch updates it in place.
    var refundApproval: String?
    let eventEndAt: String?
    let readOnlyAt: String?
    let readOnly: Bool

    enum CodingKeys: String, CodingKey {
        case channels
        case eventId = "event_id", refundApproval = "refund_approval", eventEndAt = "event_end_at"
        case readOnlyAt = "read_only_at", readOnly = "read_only"
    }
}

struct ProjectEvent: Decodable, Equatable {
    let id: String
    let name: String
    let eventDate: String?
    let eventTime: String?
    let startsAt: String?
    let tz: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, tz, status
        case eventDate = "event_date", eventTime = "event_time", startsAt = "starts_at"
    }
    var timeZone: TimeZone { tz.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Asia/Ho_Chi_Minh")! }
}

struct ProjectMe: Decodable, Equatable {
    let memberId: String
    let role: String
    let laneId: String?
    let capMoney: Bool
    let capCheckin: Bool
    let grantExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case role
        case memberId = "member_id", laneId = "lane_id", capMoney = "cap_money", capCheckin = "cap_checkin"
        case grantExpiresAt = "grant_expires_at"
    }
}

struct ProjectPerson: Decodable, Equatable, Identifiable {
    let userId: String
    let displayName: String?
    let handle: String?
    let avatarUrl: String?
    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case handle
        case userId = "user_id", displayName = "display_name", avatarUrl = "avatar_url"
    }
}

struct ProjectMember: Decodable, Equatable, Identifiable {
    let memberId: String
    let userId: String
    let role: String
    let laneId: String?
    let capMoney: Bool
    let capCheckin: Bool
    let displayName: String?
    let handle: String?
    let avatarUrl: String?
    var id: String { memberId }

    enum CodingKeys: String, CodingKey {
        case role, handle
        case memberId = "member_id", userId = "user_id", laneId = "lane_id", capMoney = "cap_money", capCheckin = "cap_checkin"
        case displayName = "display_name", avatarUrl = "avatar_url"
    }
}

struct ProjectLane: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let position: Int
}

struct ProjectTask: Decodable, Equatable, Identifiable {
    let id: String
    let laneId: String
    var title: String
    var assigneeId: String?
    /// "yyyy-MM-dd", a day in the EVENT's zone.
    var dueDate: String?
    var status: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case laneId = "lane_id", assigneeId = "assignee_id", dueDate = "due_date", createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct ProjectPost: Decodable, Equatable, Identifiable {
    let id: String
    let laneId: String
    let type: String
    var title: String
    var body: String
    let authorId: String?
    let addresseeId: String?
    let options: [String]?
    let deadline: String?
    var state: String
    let createdAt: String?
    var editedAt: String?
    var votes: [Int]?
    var myVote: Int?
    var repliesCount: Int
    var seenCount: Int
    var seenByMe: Bool
    var quiet: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, options, deadline, state, votes, quiet
        case laneId = "lane_id", authorId = "author_id", addresseeId = "addressee_id", createdAt = "created_at", editedAt = "edited_at"
        case myVote = "my_vote", repliesCount = "replies_count", seenCount = "seen_count", seenByMe = "seen_by_me"
    }
}

struct ProjectRosItem: Decodable, Equatable, Identifiable {
    let id: String
    var title: String
    var ownerId: String?
    var startsAt: String
    var endsAt: String
    var doneAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case ownerId = "owner_id", startsAt = "starts_at", endsAt = "ends_at", doneAt = "done_at"
    }
}

struct ProjectChangeRequest: Decodable, Equatable, Identifiable {
    let id: String
    let kind: String
    let laneId: String?
    let payload: ProjectChangePayload
    let why: String
    let status: String
    let proposedBy: String?
    let decisionReason: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, why, status
        case laneId = "lane_id", proposedBy = "proposed_by", decisionReason = "decision_reason"
    }
}

/// The parts of a change request's payload the app shows (lane name; a channel's URL / label).
struct ProjectChangePayload: Decodable, Equatable {
    let name: String?
    let url: String?
    let channel: ProjectChannels.Channel?
}

/// One of the many write RPCs: {success, error, …}.
struct ProjectWriteResult: Decodable {
    let success: Bool
    let error: String?
}

struct MyProjectsResult: Decodable {
    let success: Bool
    let projects: [MyProject]?
}

struct MyProject: Decodable, Equatable, Identifiable {
    let eventId: String
    let name: String
    let eventDate: String?
    let startsAt: String?
    let tz: String?
    let status: String?
    let role: String
    let myOpenTasks: Int
    let readOnly: Bool
    var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case name, tz, status, role
        case eventId = "event_id", eventDate = "event_date", startsAt = "starts_at", myOpenTasks = "my_open_tasks", readOnly = "read_only"
    }
}

enum ProjectDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    /// A server timestamp, with or without fractional seconds.
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - phase 4: topics, invites, join

/// `get_event_project_post`: one post with its replies, who voted what and who has seen it.
struct ProjectPostDetail: Decodable, Equatable {
    let success: Bool
    let error: String?
    var post: ProjectPost?
    var replies: [ProjectReply]?
    var voters: [ProjectVoter]?
    var seenBy: [String]?

    enum CodingKeys: String, CodingKey {
        case success, error, post, replies, voters
        case seenBy = "seen_by"
    }
}

struct ProjectReply: Decodable, Equatable, Identifiable {
    let id: String
    let authorId: String?
    let body: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorId = "author_id", createdAt = "created_at"
    }
}

struct ProjectVoter: Decodable, Equatable {
    let userId: String
    let optionIndex: Int

    enum CodingKeys: String, CodingKey { case userId = "user_id", optionIndex = "option_index" }
}

/// `get_event_project_posts`: an older page of posts.
struct ProjectPostsPage: Decodable {
    let success: Bool
    let error: String?
    let posts: [ProjectPost]?
}

/// `project_create_invite` returns one of these; `project_list_invites` a list (with `uses`).
struct ProjectInvite: Decodable, Equatable, Identifiable {
    let inviteId: String
    let token: String
    let shortCode: String
    let role: String
    let laneId: String?
    let expiresAt: String?
    let maxUses: Int?
    let uses: Int?
    let createdBy: String?
    var id: String { inviteId }

    enum CodingKeys: String, CodingKey {
        case token, role, uses
        case inviteId = "invite_id", shortCode = "short_code", laneId = "lane_id", expiresAt = "expires_at", maxUses = "max_uses"
        case createdBy = "created_by"
    }
}

struct ProjectInviteResult: Decodable {
    let success: Bool
    let error: String?
    let inviteId: String?
    let token: String?
    let shortCode: String?
    let role: String?
    let laneId: String?
    let expiresAt: String?
    let maxUses: Int?

    enum CodingKeys: String, CodingKey {
        case success, error, token, role
        case inviteId = "invite_id", shortCode = "short_code", laneId = "lane_id", expiresAt = "expires_at", maxUses = "max_uses"
    }

    var invite: ProjectInvite? {
        guard success, let inviteId, let token, let shortCode, let role else { return nil }
        return ProjectInvite(inviteId: inviteId, token: token, shortCode: shortCode, role: role, laneId: laneId, expiresAt: expiresAt,
                             maxUses: maxUses, uses: 0, createdBy: nil)
    }
}

struct ProjectInviteList: Decodable {
    let success: Bool
    let error: String?
    let invites: [ProjectInvite]?
}

/// `peek_project_invite`: what a link or typed code points at, before joining. `state` is ok, revoked, expired, used,
/// event_closed, is_host or already_member.
struct ProjectInvitePeek: Decodable, Equatable {
    let success: Bool
    let error: String?
    let state: String?
    let eventId: String?
    let eventName: String?
    let eventDate: String?
    let startsAt: String?
    let tz: String?
    let organizerName: String?
    let role: String?
    let laneName: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case success, error, state, tz, role
        case eventId = "event_id", eventName = "event_name", eventDate = "event_date", startsAt = "starts_at"
        case organizerName = "organizer_name", laneName = "lane_name", expiresAt = "expires_at"
    }
}

struct ProjectRedeemResult: Decodable {
    let success: Bool
    let error: String?
    let eventId: String?
    let role: String?

    enum CodingKeys: String, CodingKey { case success, error, role, eventId = "event_id" }
}

// MARK: - phase 5: day-of and trash

/// `get_event_project_ros`: the event-day poll ({unchanged} when nothing moved).
struct ProjectRosResult: Decodable {
    let success: Bool
    let error: String?
    let unchanged: Bool?
    let version: Int?
    let ros: [ProjectRosItem]?
}

/// `get_event_project_trash`: deleted tasks, posts and run-of-show items (7 days) and archived lanes.
struct ProjectTrashResult: Decodable {
    let success: Bool
    let error: String?
    let items: [ProjectTrashItem]?
}

struct ProjectTrashItem: Decodable, Equatable, Identifiable {
    let kind: String
    let itemId: String
    let title: String
    let by: String?
    let reason: String?
    let at: String?
    let startsAt: String?
    var id: String { "\(kind).\(itemId)" }

    enum CodingKeys: String, CodingKey {
        case kind, title, by, reason, at
        case itemId = "id", startsAt = "starts_at"
    }
}

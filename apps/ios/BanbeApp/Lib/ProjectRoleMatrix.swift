import Foundation

/// The Team tab's "Who can do what" table (v6 prototype, five columns: Host, Manager, Finance & door, Lane lead,
/// Helper). Data only; `ProjectRoleMatrixTests` checks every cell that names an `action` against `ProjectPermissions`,
/// so the table can never promise something the rules (and the server) refuse.
enum ProjectRoleMatrix {
    enum Cell: Equatable {
        case yes, no
        /// Only in their own lane.
        case lane
        /// The Host can grant it (money / check-in capability).
        case grant
        /// Proposes; the Host approves.
        case propose
    }

    /// What the permission check is asked with for a row (the test builds the target from it).
    enum Probe: Equatable { case plain, ownTask, ownQuietPost, laneScoped, roleHelper }

    struct Row: Identifiable, Equatable {
        let id: String
        let vi: String
        let en: String
        /// The `ProjectPermissions` action behind the row; nil = not a project action (payout, cancelling the event).
        let action: String?
        let probe: Probe
        /// Host, Manager, Finance & door, Lane lead, Helper.
        let cells: [Cell]
    }

    static let columns = ["host", "manager", "finance", "lane_lead", "helper"]

    static let rows: [Row] = [
        Row(id: "read", vi: "Xem mọi thứ (trừ tiền)", en: "See everything (not money)", action: "project.read", probe: .plain,
            cells: [.yes, .yes, .yes, .yes, .yes]),
        Row(id: "ownTask", vi: "Cập nhật việc của mình", en: "Update own tasks", action: "task.status", probe: .ownTask,
            cells: [.yes, .yes, .yes, .yes, .yes]),
        Row(id: "ask", vi: "Hỏi, cập nhật, bỏ phiếu", en: "Ask, post updates, vote", action: "post.question", probe: .plain,
            cells: [.yes, .yes, .yes, .yes, .yes]),
        Row(id: "proposal", vi: "Đăng đề xuất", en: "Post proposals", action: "post.proposal", probe: .plain,
            cells: [.yes, .yes, .yes, .yes, .no]),
        Row(id: "tasks", vi: "Tạo, giao, sửa, xoá việc", en: "Create, assign, edit, delete tasks", action: "task.manage", probe: .laneScoped,
            cells: [.yes, .yes, .no, .lane, .no]),
        Row(id: "decide", vi: "Chốt quyết định", en: "Make decisions", action: "post.decision", probe: .laneScoped,
            cells: [.yes, .yes, .no, .lane, .no]),
        Row(id: "ownPost", vi: "Sửa, xoá bài của mình (khi chưa ai phản hồi)", en: "Edit or delete own posts (before anyone responds)",
            action: "post.edit", probe: .ownQuietPost, cells: [.yes, .yes, .yes, .yes, .yes]),
        Row(id: "otherPost", vi: "Xoá bài của người khác", en: "Delete others’ posts", action: "post.delete", probe: .plain,
            cells: [.yes, .yes, .no, .no, .no]),
        Row(id: "invite", vi: "Mời người", en: "Invite people", action: "invite.create", probe: .roleHelper,
            cells: [.yes, .yes, .no, .no, .no]),
        Row(id: "roles", vi: "Đổi vai, cấp quyền", en: "Change roles, grant access", action: "member.manage", probe: .plain,
            cells: [.yes, .no, .no, .no, .no]),
        Row(id: "lanes", vi: "Thêm, đổi tên, lưu trữ hạng mục", en: "Add, rename, archive lanes", action: "lane.manage", probe: .plain,
            cells: [.yes, .propose, .no, .no, .no]),
        Row(id: "channels", vi: "Sửa kênh của đội", en: "Edit team channels", action: "channels.edit", probe: .plain,
            cells: [.yes, .propose, .no, .no, .no]),
        Row(id: "review", vi: "Duyệt đề xuất hạng mục, kênh", en: "Review lane and channel proposals", action: "change.review", probe: .plain,
            cells: [.yes, .no, .no, .no, .no]),
        Row(id: "ros", vi: "Sửa chương trình ngày diễn ra", en: "Edit the run-of-show", action: "ros.edit", probe: .plain,
            cells: [.yes, .yes, .no, .no, .no]),
        Row(id: "restore", vi: "Khôi phục từ thùng rác", en: "Restore from the trash", action: "trash.restore", probe: .plain,
            cells: [.yes, .yes, .no, .no, .no]),
        Row(id: "purge", vi: "Xoá vĩnh viễn", en: "Delete permanently", action: "trash.purge", probe: .plain,
            cells: [.yes, .no, .no, .no, .no]),
        Row(id: "money", vi: "Xem tiền, xác nhận thanh toán", en: "See money, confirm payments", action: "money.confirm", probe: .plain,
            cells: [.yes, .grant, .yes, .grant, .grant]),
        Row(id: "checkin", vi: "Check-in khách", en: "Check guests in", action: "checkin", probe: .plain,
            cells: [.yes, .grant, .yes, .grant, .grant]),
        Row(id: "payout", vi: "Đổi tài khoản nhận tiền, huỷ sự kiện", en: "Change payout account, cancel event", action: nil, probe: .plain,
            cells: [.yes, .no, .no, .no, .no]),
    ]
}

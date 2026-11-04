// The Team tab's "Who can do what" table (v6 prototype; columns Host, Manager, Finance & door, Lane lead, Helper).
// iOS twin: apps/ios/BanbeApp/Lib/ProjectRoleMatrix.swift (same rows). tests/unit/projectRoleMatrix.test.mjs checks every
// cell that names an action against canProject(), so the table can never promise something the rules refuse.
// Cells: yes, no, lane (own lane only), grant (the Host can grant it), propose (proposes, the Host approves).
export const MATRIX_COLUMNS = ['host', 'manager', 'finance', 'lane_lead', 'helper'];

export const MATRIX_ROWS = [
  { id: 'read', vi: 'Xem mọi thứ (trừ tiền)', en: 'See everything (not money)', action: 'project.read', probe: 'plain', cells: ['yes', 'yes', 'yes', 'yes', 'yes'] },
  { id: 'ownTask', vi: 'Cập nhật việc của mình', en: 'Update own tasks', action: 'task.status', probe: 'ownTask', cells: ['yes', 'yes', 'yes', 'yes', 'yes'] },
  { id: 'ask', vi: 'Hỏi, cập nhật, bỏ phiếu', en: 'Ask, post updates, vote', action: 'post.question', probe: 'plain', cells: ['yes', 'yes', 'yes', 'yes', 'yes'] },
  { id: 'proposal', vi: 'Đăng đề xuất', en: 'Post proposals', action: 'post.proposal', probe: 'plain', cells: ['yes', 'yes', 'yes', 'yes', 'no'] },
  { id: 'tasks', vi: 'Tạo, giao, sửa, xoá việc', en: 'Create, assign, edit, delete tasks', action: 'task.manage', probe: 'laneScoped', cells: ['yes', 'yes', 'no', 'lane', 'no'] },
  { id: 'decide', vi: 'Chốt quyết định', en: 'Make decisions', action: 'post.decision', probe: 'laneScoped', cells: ['yes', 'yes', 'no', 'lane', 'no'] },
  { id: 'ownPost', vi: 'Sửa, xoá bài của mình (khi chưa ai phản hồi)', en: 'Edit or delete own posts (before anyone responds)', action: 'post.edit', probe: 'ownQuietPost', cells: ['yes', 'yes', 'yes', 'yes', 'yes'] },
  { id: 'otherPost', vi: 'Xoá bài của người khác', en: 'Delete others’ posts', action: 'post.delete', probe: 'plain', cells: ['yes', 'yes', 'no', 'no', 'no'] },
  { id: 'invite', vi: 'Mời người', en: 'Invite people', action: 'invite.create', probe: 'roleHelper', cells: ['yes', 'yes', 'no', 'no', 'no'] },
  { id: 'roles', vi: 'Đổi vai, cấp quyền', en: 'Change roles, grant access', action: 'member.manage', probe: 'plain', cells: ['yes', 'no', 'no', 'no', 'no'] },
  { id: 'lanes', vi: 'Thêm, đổi tên, lưu trữ hạng mục', en: 'Add, rename, archive lanes', action: 'lane.manage', probe: 'plain', cells: ['yes', 'propose', 'no', 'no', 'no'] },
  { id: 'channels', vi: 'Sửa kênh của đội', en: 'Edit team channels', action: 'channels.edit', probe: 'plain', cells: ['yes', 'propose', 'no', 'no', 'no'] },
  { id: 'review', vi: 'Duyệt đề xuất hạng mục, kênh', en: 'Review lane and channel proposals', action: 'change.review', probe: 'plain', cells: ['yes', 'no', 'no', 'no', 'no'] },
  { id: 'ros', vi: 'Sửa chương trình ngày diễn ra', en: 'Edit the run-of-show', action: 'ros.edit', probe: 'plain', cells: ['yes', 'yes', 'no', 'no', 'no'] },
  { id: 'restore', vi: 'Khôi phục từ thùng rác', en: 'Restore from the trash', action: 'trash.restore', probe: 'plain', cells: ['yes', 'yes', 'no', 'no', 'no'] },
  { id: 'purge', vi: 'Xoá vĩnh viễn', en: 'Delete permanently', action: 'trash.purge', probe: 'plain', cells: ['yes', 'no', 'no', 'no', 'no'] },
  { id: 'money', vi: 'Xem tiền, xác nhận thanh toán', en: 'See money, confirm payments', action: 'money.confirm', probe: 'plain', cells: ['yes', 'grant', 'yes', 'grant', 'grant'] },
  { id: 'checkin', vi: 'Check-in khách', en: 'Check guests in', action: 'checkin', probe: 'plain', cells: ['yes', 'grant', 'yes', 'grant', 'grant'] },
  { id: 'payout', vi: 'Đổi tài khoản nhận tiền, huỷ sự kiện', en: 'Change payout account, cancel event', action: null, probe: 'plain', cells: ['yes', 'no', 'no', 'no', 'no'] },
];

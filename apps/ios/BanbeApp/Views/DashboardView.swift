import SwiftUI
import PhotosUI

/// Port of src/screens/Dashboard.jsx — the organizer's own page: verify
/// badge, upcoming events each with a check-in button, past events, and
/// "create new event" pinned at the bottom.
struct DashboardView: View {
    @EnvironmentObject var app: AppState
    // STAGE C (2026-09-25) — the real "add a photo to one of my own
    // events" flow; one shared picker item/target-event pair (same
    // pattern EditProfileView's own avatar picker uses), since there's one
    // instance of this control per event row rather than a single one.
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var photoPickerEventID: String?
    @State private var creditEventID: String = ""
    @State private var creditUserID: String = ""
    /// Remaining-resubmission-attempts hint's own next-eligible-time
    /// display (migration 107) — plain locale-default formatting, same as
    /// web's `Date.toLocaleString()`.
    static let nextEligibleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// Branded from one of this account's real events when it owns any
    /// (myOrgEventKeys), falling back to the open event otherwise.
    private var event: CatalogEvent {
        if let key = app.myOrgEventKeys.first, let owned = EventCatalog.find(key) { return owned }
        return app.currentEvent
    }

    // TASK 3 — was a raw static-catalogue filter with no live status
    // merged in; now backed by `AppState.myOrgEvents`, which applies the
    // same real `withLive`/`applyingLiveStatus` merge Home already uses,
    // so a genuinely-ended real event actually drops out of `upcoming`
    // (and its Check-in button) instead of staying there forever.
    private var myEvents: [CatalogEvent] { app.myOrgEvents }
    private var upcoming: [CatalogEvent] {
        myEvents.filter { $0.isOpen }.sorted { ($0.until ?? 999) < ($1.until ?? 999) }
    }
    private var past: [CatalogEvent] {
        myEvents.filter { !$0.cancelled && $0.endedHoursAgo != nil }
            .sorted { ($0.endedHoursAgo ?? 0) < ($1.endedHoursAgo ?? 0) }
    }

    /// THIRD STALE-AVATAR SITE (2026-09-28) — this header's round avatar
    /// used to always be `CatalogPhoto(path: event.img, ...)`, the static
    /// demo-catalogue event photo, never `app.myOrganizerAvatarPath` (the
    /// canonical source Account/OrganizerProfileView already read, kept
    /// fresh in place by saveOrganizerProfile's success branch) — so a
    /// real host's photo change never showed here at all, stale or not.
    /// Same pattern as OrganizerProfileView's own `organizerAvatarURL`.
    private var organizerAvatarURL: URL? {
        guard app.myOrganizerID != nil, !app.myOrganizerAvatarPath.isEmpty else { return nil }
        return MediaURLs.organizerAvatar(path: app.myOrganizerAvatarPath, r2Ref: app.myOrganizerAvatarR2Ref, variant: .card)
    }

    private var verifyLabel: String {
        if event.orgTrusted { return app.T("Đã xác minh", "Verified") }
        return app.orgVerifyRequested ? app.T("Đang xác minh", "Verifying")
                                      : app.T("Chưa xác minh", "Not verified")
    }

    /// TASK A (2026-10-01 UX foundation pass) — Dashboard is host-only (this
    /// whole screen only ever renders for an organizer), so only host
    /// sources apply here.
    private var actionItems: [ActionCenterItem] {
        buildActionCenterItems(ActionCenterInputs(
            role: .host, now: Date(),
            verifications: app.verifications, refundQueue: app.refundQueue, orgHolding: app.organizerHoldingSummary,
            onOpenVerifications: { app.openVerifications(back: .dashboard) },
            onOpenRefundCenter: { app.openVerifications(back: .dashboard) },
            onOpenDashboard: {},
            // A single open dispute goes straight to that dispute's own
            // conversation rather than to the queue in front of it.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        ))
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button { app.backFromDashboard() } label: {
                                HStack(spacing: 6) {
                                    Text("‹").font(.system(size: 14))
                                    BanbeLogo(kind: .mark, height: 34)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        HStack(spacing: 14) {
                            // Real organizer avatar when this account has
                            // one; `event.img`'s demo-catalogue photo is
                            // only the fallback for a never-hosted
                            // dev/seed account, same fallback rule the org
                            // name/stats lines just below already follow.
                            if let url = organizerAvatarURL {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                                    .accessibilityIdentifier("dashboard.organizerAvatar")
                            } else {
                                CatalogPhoto(path: event.img, height: 56, width: 56, cornerRadius: 28)
                                    .accessibilityIdentifier("dashboard.organizerAvatarFallback")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                // Personal-vs-organizer hierarchy pass
                                // (2026-09-27) — the real organizers.name
                                // (app.orgRegName, kept in sync by
                                // loadMyOrgStats/saveOrganizerProfile) once
                                // this account actually has one; the demo-
                                // catalogue event.orgName is only ever a
                                // fallback for a never-hosted dev/seed
                                // account.
                                Text(app.orgRegName.isEmpty ? event.orgName : app.orgRegName).font(BanbeTheme.display(24))
                                // Real owner, never guessed/invented — this
                                // screen only ever renders for the signed-in
                                // account's OWN organizer, so the viewer IS
                                // the owner. Never persisted as part of the
                                // name itself ("Team" is display-only text).
                                if app.myOrganizerID != nil {
                                    Text(app.T("Bởi \(app.displayName) Team", "By \(app.displayName) Team"))
                                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                                        .accessibilityIdentifier("dashboard.ownerLine")
                                }
                                Text(verifyLabel)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .overlay(Capsule().stroke(
                                        event.orgTrusted || app.orgVerifyRequested ? app.palette.ink : app.palette.rule,
                                        lineWidth: 1))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 16)

                        // Live track record of this account's own organizer (never the
                        // demo catalogue's baked-in numbers).
                        if let id = app.myOrganizerID, let stats = app.organizerStats[id], stats.count > 0 {
                            Text(stats.sinceYear.map { year in
                                app.T("Tổ chức từ \(year) ▪︎ \(stats.count) sự kiện", "Hosting since \(year) ▪︎ \(stats.count) events")
                            } ?? app.T("\(stats.count) sự kiện", "\(stats.count) events"))
                            .font(.system(size: 12.5))
                            .padding(.top, 14)
                        }

                        // Personal-vs-organizer hierarchy pass (2026-09-27)
                        // — replaces the former "Chỉnh sửa"/"Xem như khách"
                        // pair with ONE clear action: opens the
                        // organizer's own separate public page
                        // (OrganizerProfileView — real avatar/stats/
                        // upcoming events/photos, its own shareable
                        // /org/<id> link and, for the owner only, its own
                        // "Chỉnh sửa hồ sơ tổ chức" entry), never the
                        // personal profile editor. Event management
                        // controls stay here.
                        if let organizerID = app.myOrganizerID {
                            Button(app.T("Hồ sơ công khai của tổ chức", "Organizer's public profile")) {
                                app.openOrganizerProfile(organizerID: organizerID, back: .dashboard)
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                            .foregroundStyle(app.palette.ink)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dashboard.organizerPublicProfile")
                            .padding(.top, 16)

                            teamSection(organizerID: organizerID)
                        }

                        if !event.orgTrusted && !app.orgVerifyRequested {
                            HStack(spacing: 12) {
                                Text(app.T("Xác minh hồ sơ để khách tin tưởng hơn.",
                                           "Get verified so guests trust you faster."))
                                    .font(.system(size: 12.5))
                                    .lineSpacing(3)
                                Spacer(minLength: 0)
                                Button(app.T("Yêu cầu xác minh", "Request")) { app.requestVerify() }
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(app.palette.paper)
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .background(app.palette.ink, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                            .padding(16)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 16)
                        }

                        // TASK A (2026-10-01 UX foundation pass) — host-only
                        // Action Center (this screen only ever renders for
                        // an organizer).
                        ActionCenterView(items: actionItems, onSeeAll: { app.openVerifications(back: .dashboard) }, horizontalInset: 0)

                        // Event review queue — a real submission's own
                        // status/reason, never the static catalogue.
                        // Pending: still awaiting an admin decision.
                        // Needs fixing: rejected (status flipped back to
                        // 'draft' by admin_review_event, migration 085) —
                        // "Sửa & gửi lại" opens CreateEventView pre-filled
                        // (goEditEvent), which resubmits the SAME row
                        // (resubmit_event_for_review), never a duplicate.
                        if !app.myPendingEvents.isEmpty || !app.myNeedsFixEvents.isEmpty {
                            Text(app.T("Sự kiện đã gửi", "Submitted events"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.top, 24)
                            VStack(spacing: 0) {
                                ForEach(app.myNeedsFixEvents, id: \.id) { row in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(row.name).font(BanbeTheme.display(15))
                                            Spacer()
                                            Text(app.T("Cần chỉnh sửa", "Needs fixing"))
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(BanbeTheme.alert)
                                        }
                                        Text(row.rejectionReason ?? "")
                                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.8))
                                        // Remaining-resubmission-attempts
                                        // surfacing (migration 107) — a
                                        // banbe PRODUCT POLICY limit (2 per
                                        // rolling 24h), never phrased as a
                                        // legal/Ticketbox requirement.
                                        if let resubmissionStatus = app.resubmissionStatusByEvent[row.id] {
                                            Text(resubmissionStatus.remaining > 0
                                                 ? app.T("Còn \(resubmissionStatus.remaining) lần gửi lại trong 24 giờ.", "\(resubmissionStatus.remaining) resubmission(s) left in the next 24h.")
                                                 : app.T("Đã hết lượt gửi lại. Thử lại sau \(DashboardView.nextEligibleFormatter.string(from: resubmissionStatus.nextEligibleAt ?? Date())).",
                                                         "Resubmission limit reached. Try again after \(DashboardView.nextEligibleFormatter.string(from: resubmissionStatus.nextEligibleAt ?? Date()))."))
                                                .font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                                                .accessibilityIdentifier("dashboard.resubmitRemaining.\(row.id)")
                                        }
                                        Button(app.T("Sửa & gửi lại", "Fix & resubmit")) { app.goEditEvent(row) }
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                                            .buttonStyle(.plain)
                                            .opacity(app.resubmissionStatusByEvent[row.id]?.remaining == 0 ? 0.4 : 1)
                                            .disabled(app.resubmissionStatusByEvent[row.id]?.remaining == 0)
                                            .accessibilityIdentifier("dashboard.resubmit.\(row.id)")
                                    }
                                    .padding(.vertical, 13).padding(.horizontal, 16)
                                    .accessibilityIdentifier("dashboard.needsFix.\(row.id)")
                                    .task(id: row.id) { await app.loadResubmissionStatus(row.id) }
                                    if row.id != app.myNeedsFixEvents.last?.id || !app.myPendingEvents.isEmpty {
                                        Divider().overlay(app.palette.rule)
                                    }
                                }
                                ForEach(app.myPendingEvents, id: \.id) { row in
                                    PendingEventRow(row: row)
                                    if row.id != app.myPendingEvents.last?.id { Divider().overlay(app.palette.rule) }
                                }
                            }
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(app.T("Sự kiện sắp tới", "Upcoming events"))
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text("\(upcoming.count)" + app.T(" sự kiện", upcoming.count == 1 ? " event" : " events"))
                                .font(.system(size: 10.5))
                        }
                        .padding(.top, 24)

                        VStack(spacing: 0) {
                            if upcoming.isEmpty {
                                Text(app.T("Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.",
                                           "No upcoming events yet. Create one below."))
                                    .font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            ForEach(upcoming) { item in
                                HStack(spacing: 12) {
                                    Button { app.goEvent(item.key) } label: {
                                        HStack(spacing: 12) {
                                            CatalogPhoto(path: item.img, height: 52, width: 52)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name).font(BanbeTheme.display(15)).lineLimit(1)
                                                Text(app.trStatus(app.stripKm(item.meta, event: item)))
                                                    .font(.system(size: 11.5)).lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    addPhotoButton(for: item.key)
                                    Button(app.T("Điểm danh", "Check-in")) { app.openAttendance(item.key) }
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                                        .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                if item.key != upcoming.last?.key { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)

                        Text(app.T("Sự kiện đã qua", "Past events"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.top, 22)

                        VStack(spacing: 0) {
                            if past.isEmpty {
                                Text(app.T("Chưa có sự kiện nào đã qua.", "No past events yet."))
                                    .font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            ForEach(past) { item in
                                HStack(spacing: 12) {
                                    Button { app.goEvent(item.key) } label: {
                                        HStack(spacing: 12) {
                                            CatalogPhoto(path: item.img, height: 52, width: 52)
                                                .saturation(0.5)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name).font(BanbeTheme.display(15)).lineLimit(1)
                                                Text(app.trStatus(app.stripKm(item.meta, event: item))
                                                     + " ▪︎ " + app.trStatus(EventLabels.ago(item.endedHoursAgo ?? 0)))
                                                    .font(.system(size: 11.5)).lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    // STAGE C — Task 1's own "ended must stay
                                    // in the library" rule implies a host
                                    // should be able to add a recap photo
                                    // after the fact, not just while live.
                                    addPhotoButton(for: item.key)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                if item.key != past.last?.key { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)

                        if !app.eventPhotoUploadError.isEmpty {
                            Text(app.eventPhotoUploadError)
                                .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                                .padding(.top, 10)
                        }
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }

                // RESTYLE (2026-09-28) — was a full-width, square-cornered
                // bar (`cornerRadius: 0`, no horizontal padding). Now a
                // plain `InkButton` at its default cornerRadius (18) — the
                // same default the "Mời thành viên" button just above
                // already uses, so shape/typography match by construction,
                // not a new eyeballed style — inset the same 22pt every
                // other row on this screen already uses, with extra bottom
                // breathing room. The VStack it sits in does NOT
                // `.ignoresSafeArea()` (only the background does, above),
                // so the home-indicator safe area is already respected;
                // same tap action and the same screen-level host-only gate
                // (this whole screen only ever renders for an organizer).
                InkButton(title: app.T("+ Tạo sự kiện mới", "+ Create new event")) {
                    app.goCreate()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
                .accessibilityIdentifier("dashboard.createEvent")
            }
        }
        .task {
            await app.loadMyEvents()
            // Event review queue — this account's own real (non-catalogue)
            // events, raw status/rejection reason included. Sequenced
            // after loadMyEvents() (not a separate parallel .task), since
            // it reads myOrgEventKeys, which THAT call is what populates.
            await app.loadMyOrgEventSummaries()
        }
        .task { await app.loadHomeLiveEvents() }
        .task { if let id = app.myOrganizerID { await app.loadOrganizerStats(organizerID: id) } }
        // Organizer Team pass (2026-09-27, Stage 1) — owner-only, the FULL
        // roster (every status); this screen only ever renders for the
        // account's own organizer.
        .task { if let organizerID = app.myOrganizerID { await app.loadOrgTeamRoster(organizerID: organizerID) } }
        // TASK A (2026-10-01 UX foundation pass).
        .task {
            await app.loadVerifications()
            await app.loadRefundQueue()
            await app.loadOrganizerHoldingSummary()
        }
        // STAGE C (2026-09-25) — the real "add a photo to one of my own
        // events" flow; one shared onChange, `photoPickerEventID` says
        // which row's tap set it (same pattern EditProfileView's own
        // avatar picker uses for a single target).
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                guard let newItem, let eventID = photoPickerEventID,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                _ = await app.uploadEventPhoto(eventID: eventID, image: image)
                photoPickerEventID = nil
            }
        }
    }

    private static let statusLabelKeys: [String: (String, String)] = [
        "invited": ("Đang chờ", "Pending"), "accepted": ("Đã tham gia", "Joined"),
        "declined": ("Đã từ chối", "Declined"), "removed": ("Đã xoá", "Removed"),
    ]

    // Organizer Team pass (2026-09-27, Stage 1) — owner-only roster
    // management. Public role is display-only (never authorization — this
    // account's own owner_id/user_id on `organizers` is still the only
    // thing any event/payment/refund/bank action ever checks). The owner
    // can invite/remove but never flip a member's own public_visible
    // switch (no control here writes that field at all).
    @ViewBuilder
    private func teamSection(organizerID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Đội ngũ", "Team")).font(.system(size: 11.5, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                TextField(app.T("Tên người dùng (@handle)", "Handle (@handle)"), text: $app.orgTeamInviteHandle)
                    .font(.system(size: 13)).accessibilityIdentifier("dashboard.team.inviteHandle")
                TextField(app.T("Vai trò công khai (VD: Điều phối)", "Public role (e.g. Coordinator)"), text: $app.orgTeamInviteRole)
                    .font(.system(size: 13)).accessibilityIdentifier("dashboard.team.inviteRole")
                if !app.orgTeamInviteError.isEmpty {
                    Text(app.orgTeamInviteError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
                InkButton(title: app.orgTeamInviteBusy ? app.T("Đang gửi…", "Sending…") : app.T("Mời thành viên", "Invite member")) {
                    Task { await app.inviteOrganizerMember(organizerID: organizerID) }
                }
                .disabled(app.orgTeamInviteBusy)
                .accessibilityIdentifier("dashboard.team.inviteSubmit")
            }
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            ForEach(app.orgTeamRoster.filter { $0.status != "removed" }) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.profiles?.displayName ?? member.profiles?.handle ?? "").font(.system(size: 13))
                        let statusLabel = Self.statusLabelKeys[member.status].map { app.T($0.0, $0.1) } ?? member.status
                        Text("\(member.publicRole) ▪︎ \(statusLabel)" + (member.status == "accepted" && !member.publicVisible ? " ▪︎ \(app.T("đã ẩn công khai", "hidden from public"))" : ""))
                            .font(.system(size: 11)).opacity(0.65)
                    }
                    Spacer()
                    Button(app.T("Xoá", "Remove")) {
                        Task { await app.removeOrganizerMember(membershipID: member.id, organizerID: organizerID) }
                    }
                    .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("dashboard.team.remove.\(member.id)")
                }
                .foregroundStyle(app.palette.ink)
                .padding(12)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("dashboard.team.member.\(member.id)")
            }

            // Organizer Team pass (2026-09-27, Stage 2) — credits a real,
            // ACCEPTED team member for a real event this account owns.
            let acceptedMembers = app.orgTeamRoster.filter { $0.status == "accepted" }
            if !app.myOrgEventSummaries.isEmpty, !acceptedMembers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("Ghi nhận đóng góp sự kiện", "Credit an event contribution")).font(.system(size: 11.5, weight: .semibold))
                    Picker(app.T("Sự kiện", "Event"), selection: $creditEventID) {
                        Text(app.T("Chọn sự kiện…", "Choose an event…")).tag("")
                        ForEach(app.myOrgEventSummaries, id: \.id) { e in Text(e.name).tag(e.id) }
                    }
                    Picker(app.T("Thành viên", "Member"), selection: $creditUserID) {
                        Text(app.T("Chọn thành viên…", "Choose a member…")).tag("")
                        ForEach(acceptedMembers) { m in Text(m.profiles?.displayName ?? m.profiles?.handle ?? "").tag(m.userId.uuidString) }
                    }
                    InkButton(title: app.T("Ghi nhận", "Credit")) {
                        guard !creditEventID.isEmpty, let uid = UUID(uuidString: creditUserID) else { return }
                        Task {
                            _ = await app.assignEventCredit(eventID: creditEventID, userID: uid)
                            creditEventID = ""; creditUserID = ""
                        }
                    }
                    .disabled(creditEventID.isEmpty || creditUserID.isEmpty)
                    .accessibilityIdentifier("dashboard.credit.submit")
                }
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func addPhotoButton(for eventID: String) -> some View {
        let busy = app.eventPhotoUploadBusy[eventID] == true
        // Resolved here, not inside PhotosPicker's label closure, which is not
        // main-actor-isolated (Swift concurrency warnings otherwise).
        let title = app.eventPhotoUploaded[eventID] == true ? app.T("Đã thêm ✓", "Added ✓")
            : busy ? app.T("Đang tải…", "Uploading…")
            : app.T("+ Ảnh", "+ Photo")
        let ruleColor = app.palette.rule
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ruleColor, lineWidth: 1))
                .opacity(busy ? 0.5 : 1)
        }
        .disabled(busy)
        .simultaneousGesture(TapGesture().onEnded { photoPickerEventID = eventID })
        .accessibilityIdentifier("dashboard.addPhoto.\(eventID)")
    }
}

/// A pending ('review') event's own row — the event name/status plus an
/// owner-only withdrawal control (migration 107, `withdraw_event_
/// submission`). iOS port of web's identical Dashboard.jsx withdraw UI:
/// requires a non-empty reason + this explicit confirm step; never deletes
/// the event row, only moves it back to editable ('draft') so
/// `goEditEvent`'s existing edit-and-resubmit path can reuse the SAME
/// event id afterwards.
struct PendingEventRow: View {
    @EnvironmentObject var app: AppState
    let row: RealEventSummary
    @State private var withdrawing = false
    @State private var reasonDraft = ""
    @State private var viewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.name).font(BanbeTheme.display(15))
                Spacer()
                Text(app.T("Đang chờ Banbe duyệt", "Waiting for Banbe to review"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
            }
            if withdrawing {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(app.T("Lý do rút lại sự kiện…", "Reason for withdrawing…"), text: $reasonDraft)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("dashboard.withdrawReason.\(row.id)")
                    if !app.withdrawEventError.isEmpty {
                        Text(app.withdrawEventError).font(.system(size: 10.5)).foregroundStyle(BanbeTheme.alert)
                    }
                    HStack(spacing: 8) {
                        Button(app.T("Xác nhận rút lại", "Confirm withdrawal")) {
                            Task {
                                let ok = await app.withdrawEventSubmission(row.id, reason: reasonDraft)
                                if ok { withdrawing = false; reasonDraft = "" }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(BanbeTheme.alert, in: RoundedRectangle(cornerRadius: 12))
                        .opacity(app.withdrawEventBusy ? 0.6 : 1)
                        .disabled(app.withdrawEventBusy)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboard.withdrawConfirm.\(row.id)")

                        Button(app.T("Huỷ", "Cancel")) { withdrawing = false; reasonDraft = ""; app.withdrawEventError = "" }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.6))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dashboard.withdrawCancel.\(row.id)")
                    }
                }
            } else {
                HStack(spacing: 14) {
                    Button { viewing = true } label: {
                        Text(app.T("Xem", "View"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16).frame(minHeight: 34)
                            .overlay(Capsule().stroke(app.palette.ink.opacity(0.5), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.viewPending.\(row.id)")
                    // Underlined: it's a tappable action, not a label.
                    Button { withdrawing = true } label: {
                        Text(app.T("Rút lại sự kiện", "Withdraw event"))
                            .font(.system(size: 12, weight: .semibold))
                            .underline()
                            .foregroundStyle(BanbeTheme.alert)
                            .frame(minHeight: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.withdraw.\(row.id)")
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .accessibilityIdentifier("dashboard.pending.\(row.id)")
        .sheet(isPresented: $viewing) { PendingEventDetailSheet(row: row) }
    }
}

/// What the host submitted, read-only, while it waits for Banbe's review.
struct PendingEventDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let row: RealEventSummary

    private var whenText: String {
        if let d = row.startsAt { return Countdown.whenLabel(for: d) }
        return [row.eventDate, row.eventTime].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
    }
    private var priceText: String {
        guard let p = row.priceVnd, p > 0 else { return app.T("Miễn phí", "Free") }
        return formatVnd(p)
    }

    @State private var photoURLs: [URL] = []
    /// nil until read — also nil if the reminder column doesn't exist yet (migration 148 not applied).
    @State private var remindCount: Int?
    @State private var remindBusy = false
    @State private var remindMessage = ""

    private var remindBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Banbe sẽ có quyết định trong vòng 7 ngày. Bạn có thể nhắc quản trị viên tối đa 2 lần cho mỗi sự kiện.",
                       "A decision will be made within 7 days. You can remind the admin up to twice per event."))
                .font(.system(size: 12.5)).opacity(0.85)
            if let used = remindCount {
                let left = max(0, 2 - used)
                Button {
                    guard !remindBusy else { return }
                    Task {
                        remindBusy = true
                        remindMessage = ""
                        let res = await app.remindAdminAboutEvent(row.id)
                        remindBusy = false
                        switch res {
                        case .sent(let n): remindCount = n; remindMessage = app.T("Đã nhắc quản trị viên.", "Reminder sent to the admin.")
                        case .limit: remindCount = 2
                        case .failed: remindMessage = app.T("Không gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if remindBusy { ProgressView() }
                        Text(left > 0 ? app.T("Nhắc quản trị viên (còn \(left) lần)", "Remind admin (\(left) left)")
                                      : app.T("Đã nhắc tối đa 2 lần", "Reminded the maximum 2 times"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(left > 0 ? app.palette.ink : app.palette.ink.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(left > 0 ? app.palette.paper : app.palette.ink.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(left == 0 || remindBusy)
                .accessibilityIdentifier("dashboard.remindAdmin.\(row.id)")
            }
            if !remindMessage.isEmpty {
                Text(remindMessage).font(.system(size: 11.5)).opacity(0.75)
            }
        }
        .padding(14)
        .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Every photo of the event (swipe sideways), not just the cover.
    @ViewBuilder private var photoStrip: some View {
        let urls = photoURLs.isEmpty ? (row.photoURL.map { [$0] } ?? []) : photoURLs
        if !urls.isEmpty {
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(urls, id: \.absoluteString) { url in
                            CatalogPhoto(path: url.absoluteString, height: 220, width: urls.count == 1 ? UIScreen.main.bounds.width - 40 : UIScreen.main.bounds.width - 70, cornerRadius: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(height: 220)
                if urls.count > 1 {
                    Text(app.T("\(urls.count) ảnh — vuốt để xem", "\(urls.count) photos — swipe to see"))
                        .font(.system(size: 11)).opacity(0.6)
                }
            }
        }
    }

    private func loadPhotos() async {
        struct P: Decodable { let storage_path: String; var r2_ref: String? = nil }
        let eid = row.id
        let rows: [P] = (try? await MediaColumns.retrying { withR2 in
            try await SupabaseService.client.from("event_photos")
                .select(MediaColumns.cols("storage_path", "r2_ref", withR2)).eq("event_id", value: eid)
                .order("sort_order", ascending: true).execute().value
        }) ?? []
        photoURLs = rows.compactMap { MediaURLs.eventPhoto(storagePath: $0.storage_path, r2Ref: $0.r2_ref, variant: .full) }
    }

    private func line(_ label: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 11)).opacity(0.6)
                    Text(value).font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    photoStrip
                    Text(row.name).font(BanbeTheme.display(24))
                    Label(app.T("Đang chờ Banbe duyệt", "Waiting for Banbe to review"), systemImage: "hourglass")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.honey)
                    remindBlock
                    line(app.T("Thời gian", "When"), whenText)
                    line(app.T("Khu vực", "Area"), row.area)
                    line(app.T("Địa chỉ", "Address"), [row.addressLine, row.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                    line(app.T("Danh mục", "Category"), row.catLabel)
                    line(app.T("Giá", "Price"), priceText)
                    line(app.T("Sức chứa", "Capacity"), row.capacity.map(String.init))
                    line(app.T("Mô tả", "Description"), row.description)
                    line(app.T("Giới thiệu", "About"), row.intro)
                    if let included = row.includedItems, !included.isEmpty {
                        line(app.T("Bao gồm", "Included"), included.map(\.label).joined(separator: " ▪︎ "))
                    }
                    line(app.T("Gửi lúc", "Submitted"), row.submittedAt?.formatted(date: .abbreviated, time: .shortened))
                }
                .padding(20)
            }
            .foregroundStyle(app.palette.ink)
            .background(app.palette.paper.ignoresSafeArea())
            .navigationTitle(app.T("Sự kiện đã gửi", "Submitted event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.T("Đóng", "Close")) { dismiss() } } }
        }
        .task { await loadPhotos() }
        .task {
            struct R: Decodable { let admin_remind_count: Int }
            if let r: R = try? await SupabaseService.client.from("events").select("admin_remind_count")
                .eq("id", value: row.id).single().execute().value { remindCount = r.admin_remind_count }
        }
        // The dock lives in its own window above the sheet — hide it while this is open.
        .onAppear { BottomTabBarOverlay.shared.setForcedHidden(true) }
        .onDisappear { BottomTabBarOverlay.shared.setForcedHidden(false) }
    }
}

/// Port of src/screens/HostIntro.jsx — what an organizer's page will look
/// like before they've posted anything.
struct HostIntroView: View {
    @EnvironmentObject var app: AppState

    private var points: [(String, String)] {
        [
            (app.T("Nhận thanh toán", "Take payments"), app.T("MoMo ▪︎ VNPay ▪︎ chuyển khoản", "MoMo ▪︎ VNPay ▪︎ bank transfer")),
            (app.T("Danh sách khách", "Guest list"), app.T("Điểm danh ngay tại cửa", "Check in at the door")),
            (app.T("Tin nhắn", "Messages"), app.T("Khách nhắn trực tiếp cho bạn", "Guests message you directly")),
            (app.T("Chi phí", "Cost"), app.T("Không phí đăng, không phí giao dịch", "No listing fee, no transaction fee")),
        ]
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BackLink(label: app.T("Tài khoản", "Account")) { app.goProfile() }

                        Text(app.T("Dành cho người tổ chức", "For organizers"))
                            .font(.system(size: 11.5))
                            .padding(.top, 16)
                        Text(app.T("Trang tổ chức của bạn, trước khi bạn đăng gì",
                                   "Your organizer page, before you post anything"))
                            .font(BanbeTheme.display(27))
                            .padding(.top, 8)
                        Text(app.T(
                            "Đây là trang khách sẽ thấy khi họ bấm vào tên bạn. Sự kiện, ảnh và số liệu sẽ tự điền vào sau mỗi lần bạn tổ chức.",
                            "This is what guests see when they tap your name. Events, photos and numbers fill in as you host."
                        ))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(app.T("Khách sẽ thấy", "Guests will see")).font(.system(size: 10.5))
                                Spacer()
                                Text("banbe").font(.system(size: 10.5))
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(app.orgRegName.isEmpty ? "Bếp Nhỏ" : app.orgRegName)
                                    .font(BanbeTheme.display(24))
                                Text(app.T("Mới", "New"))
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(app.palette.ink.opacity(0.1), in: Capsule())
                            }
                            .padding(.top, 12)
                            Text(app.orgRegIg.isEmpty ? "@bepnho.saigon" : app.orgRegIg)
                                .font(.system(size: 12.5))
                                .padding(.top, 5)
                            Text(app.orgRegDesc.isEmpty
                                 ? app.T("Mình nấu cho người lạ từ 2021…", "I cook for strangers since 2021…")
                                 : app.orgRegDesc)
                                .font(.system(size: 13))
                                .lineSpacing(3)
                                .padding(.top, 12)
                            HStack(spacing: 14) {
                                BanbeLogo(kind: .mark, width: 38, height: 38)
                                    .opacity(0.75)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.T("Chưa có sự kiện nào", "No events yet"))
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text(app.T("Sự kiện đầu tiên của bạn sẽ nằm ở đây.", "Your first event will sit here."))
                                        .font(.system(size: 11.5))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 18)
                        }
                        .padding(18)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 22)

                        VStack(spacing: 0) {
                            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(point.0).font(.system(size: 13.5, weight: .semibold))
                                    Spacer(minLength: 0)
                                    Text(point.1).font(.system(size: 12.5)).multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 13)
                                if index < points.count - 1 { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .padding(.top, 26)

                        Text(app.T("banbe duyệt sự kiện đầu tiên trong 48 giờ. Sau đó bạn đăng trực tiếp.",
                                   "banbe reviews your first event within 48 hours. After that you post directly."))
                            .font(.system(size: 11.5))
                            .lineSpacing(3)
                            .padding(.top, 16)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }

                InkButton(title: app.T("Tạo sự kiện đầu tiên", "Create your first event"), cornerRadius: 999) {
                    app.goCreate()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
}

import SwiftUI

/// L2 guest recap card (switch `event_recap`, migration 199) — the iOS counterpart of src/screens/EventRecap.jsx.
/// What a ticket holder sees after an event ends, from the event_recap notification or the ended Event Detail
/// ("You went ✓"): the event, its photos, Follow host, Next from this host, and a PRIVATE 👍/👎 + note that only the
/// host sees, as counts and unnamed notes, once 3 or more guests answered (the server enforces all of it). No public
/// rating, no streak, no nudging.
struct EventRecapView: View {
    @EnvironmentObject private var app: AppState
    @State private var hostNext: [AppState.HostUpcomingEvent] = []
    @State private var loaded = false
    @State private var saved: AppState.MyFeedback?
    @State private var rating: Int?
    @State private var note = ""
    @State private var busy = false
    @State private var error = ""
    @State private var closed = false
    @State private var justSaved = false
    @FocusState private var noteFocused: Bool

    private var eventID: String? { app.eventRecapID }
    private var event: CatalogEvent? { eventID.flatMap { app.resolvedEvent(for: $0) } }
    private var organizerID: String? { eventID.flatMap { app.eventOrganizerID[$0] } ?? event?.organizerId }

    private var photos: [PhotoGalleryItem] {
        guard let eventID else { return [] }
        return app.eventPhotos.compactMap { photo in
            guard let url = app.eventPhotoURLs[photo.id] else { return nil }
            return PhotoGalleryItem(id: photo.id.uuidString.lowercased(), url: url.absoluteString, eventId: eventID)
        }
    }

    private var windowOpen: Bool { CoreLoops.feedbackWindowOpen(startsAt: event?.startDate) && !closed }
    private var dirty: Bool {
        rating != saved?.rating || note.trimmingCharacters(in: .whitespacesAndNewlines) != (saved?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool { CoreLoops.canSaveFeedback(rating: rating, note: note) && dirty && !busy }

    private var backLabel: String {
        switch app.eventRecapBack {
        case .notifications: return app.T("Thông báo", "Notifications")
        case .event: return app.T("Sự kiện", "Event")
        default: return app.backLabel(for: app.eventRecapBack)
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: backLabel) { app.goBack() }
                    .padding(.top, 8)
                    .accessibilityIdentifier("eventRecap.back")
                if !app.eventRecapEnabled {
                    Text(app.T("Tính năng này đang tạm tắt.", "This is turned off for now."))
                        .font(.system(size: 13.5)).opacity(0.7).padding(.top, 18)
                        .accessibilityIdentifier("eventRecap.off")
                } else if let event, let eventID {
                    content(event, eventID: eventID)
                } else {
                    Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13.5)).opacity(0.7).padding(.top, 18)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.bottom, 48)
        }
        .task(id: eventID) { await load() }
    }

    private func load() async {
        loaded = false; saved = nil; rating = nil; note = ""; error = ""; closed = false; justSaved = false; hostNext = []
        guard let eventID, app.eventRecapEnabled, app.userID != nil else { return }
        await app.loadMissingRealEvents(for: [eventID])
        async let photosLoad: Void = app.loadEventPhotos(eventID: eventID)
        let fb = await app.fetchMyEventFeedback(eventID: eventID)
        guard eventID == app.eventRecapID else { return }
        saved = fb
        rating = fb?.rating
        note = fb?.note ?? ""
        loaded = true
        _ = await photosLoad
        if let orgID = organizerID {
            let rows = await app.nextFromHost(organizerID: orgID, excluding: eventID)
            if eventID == app.eventRecapID { hostNext = rows }
        }
    }

    @ViewBuilder
    private func content(_ event: CatalogEvent, eventID: String) -> some View {
        Text(app.T("Sự kiện đã kết thúc", "This event has ended"))
            .font(.system(size: 11.5, weight: .semibold)).opacity(0.7).padding(.top, 14)
        Button { app.goEvent(eventID) } label: {
            Text(event.name).font(BanbeTheme.display(26)).multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("eventRecap.title")
        if let start = event.startDate {
            Text(app.discoveryWhenLabel(start, timeZone: event.timeZoneID.map { EventMarket.timeZone($0) }))
                .font(.system(size: 13)).opacity(0.7).padding(.top, 6)
        }

        photosSection(organizer: event.orgName).padding(.top, 24)
        feedbackSection(eventID: eventID).padding(.top, 28)
        if let orgID = organizerID { hostSection(orgID).padding(.top, 28) }
    }

    // MARK: Photos — the same event_photos the event page shows, opened in the same viewer.

    @ViewBuilder
    private func photosSection(organizer: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.T("Hình ảnh", "Photos")).font(BanbeTheme.display(20))
                Spacer()
                if !photos.isEmpty { Text("\(photos.count)").font(.system(size: 13)).opacity(0.6) }
            }
            if app.eventPhotosLoading {
                Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13)).opacity(0.6).padding(.top, 10)
            } else if photos.isEmpty {
                Text(app.T("Host chưa đăng ảnh nào.", "The host hasn't posted photos yet."))
                    .font(.system(size: 13)).opacity(0.6).padding(.top, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            GeometryReader { geo in
                                Button {
                                    app.openPhoto(gallery: photos, index: index, organizer: organizer, originRect: geo.frame(in: .global))
                                } label: {
                                    CatalogPhoto(path: photo.url, height: 146, width: 116, cornerRadius: BanbeTheme.Radius.thumb)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: 116, height: 146)
                            .accessibilityIdentifier("eventRecap.photo.\(index)")
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: Private feedback — only the host sees it, as counts and unnamed notes, from 3 answers.

    private func ratingButton(_ value: Int, emoji: String, label: String, id: String) -> some View {
        let on = rating == value
        return Button {
            guard windowOpen else { return }
            Haptics.selection()
            rating = value
            justSaved = false
        } label: {
            Text(emoji).font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(on ? app.palette.clay.opacity(0.12) : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? app.palette.clay : app.palette.rule, lineWidth: 1))
                .contentShape(Capsule())
                .opacity(!windowOpen && !on ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!windowOpen)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func feedbackSection(eventID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.T("Buổi này thế nào?", "How was it?")).font(BanbeTheme.display(20))
            Text(app.T(CoreLoops.privacyLine.vi, CoreLoops.privacyLine.en))
                .font(.system(size: 12.5)).opacity(0.75).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventRecap.privacy")
            if !loaded {
                Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13)).opacity(0.6).padding(.top, 12)
            } else {
                HStack(spacing: 10) {
                    ratingButton(1, emoji: "👍", label: app.T("Thích", "Liked it"), id: "eventRecap.up")
                    ratingButton(-1, emoji: "👎", label: app.T("Không thích", "Didn't like it"), id: "eventRecap.down")
                }
                .padding(.top, 14)
                if windowOpen {
                    TextField(app.T("Ghi chú cho host (không bắt buộc)", "A note for the host (optional)"),
                              text: Binding(get: { note }, set: { note = CoreLoops.clampNote($0); justSaved = false }),
                              axis: .vertical)
                        .lineLimit(3...8)
                        .font(.system(size: 14))
                        .focused($noteFocused)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                        .padding(.top, 12)
                        .accessibilityIdentifier("eventRecap.note")
                    Text("\(CoreLoops.noteLength(note))/\(CoreLoops.noteMax)")
                        .font(.system(size: 11.5)).opacity(0.6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                        .accessibilityIdentifier("eventRecap.counter")
                    InkButton(title: busy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"), enabled: canSave) {
                        Task { await save(eventID: eventID) }
                    }
                    .padding(.top, 10)
                    .accessibilityIdentifier("eventRecap.save")
                    if justSaved && !dirty {
                        Text(app.T("Đã lưu. Bạn có thể sửa trong 14 ngày sau sự kiện.", "Saved. You can change it for 14 days after the event."))
                            .font(.system(size: 12.5)).opacity(0.75).padding(.top, 8)
                            .accessibilityIdentifier("eventRecap.saved")
                    }
                } else {
                    if let savedNote = saved?.note, !savedNote.isEmpty {
                        Text(savedNote).font(.system(size: 13.5)).padding(.top, 12)
                    }
                    Text(app.T("Đã đóng phần cảm nhận cho sự kiện này.", "Feedback for this event is closed."))
                        .font(.system(size: 12.5)).opacity(0.75).padding(.top, 10)
                        .accessibilityIdentifier("eventRecap.closed")
                }
                if !error.isEmpty && !closed {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 8)
                        .accessibilityIdentifier("eventRecap.error")
                }
            }
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("eventRecap.feedback")
    }

    private func save(eventID: String) async {
        guard let rating, CoreLoops.canSaveFeedback(rating: rating, note: note), !busy else { return }
        busy = true; error = ""; justSaved = false
        noteFocused = false
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = await app.submitEventFeedback(eventID: eventID, rating: rating, note: trimmed)
        busy = false
        if code == nil {
            saved = AppState.MyFeedback(rating: rating, note: trimmed)
            note = trimmed
            justSaved = true
            Haptics.success()
            return
        }
        if code == "NOT_OPEN" { closed = true }
        let msg = CoreLoops.feedbackErrorText(code)
        error = app.T(msg.vi, msg.en)
    }

    // MARK: Follow host + Next from this host (the same rule as Event Detail's ended section, Phase 1 Q3)

    private func hostSection(_ organizerID: String) -> some View {
        let following = app.isFollowing(organizerID)
        return VStack(alignment: .leading, spacing: 0) {
            Button { Task { await app.toggleFollowOrganizer(organizerID) } } label: {
                Label(following ? app.T("Đang theo dõi host ✓", "Following this host ✓") : app.T("Theo dõi host", "Follow host"),
                      systemImage: "person")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.palette.clay)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(following ? app.palette.clay.opacity(0.12) : .clear, in: Capsule())
                    .overlay(Capsule().stroke(app.palette.clay, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(following ? .isSelected : [])
            .accessibilityIdentifier("eventRecap.follow")
            if !hostNext.isEmpty {
                Text(app.T("Sự kiện tiếp theo của host", "Next from this host"))
                    .font(BanbeTheme.display(20))
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array(hostNext.enumerated()), id: \.element.id) { index, e in
                        Button { app.goEvent(e.id) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(BanbeTheme.display(15)).lineLimit(1)
                                    Text(app.discoveryWhenLabel(e.startsAt, timeZone: EventMarket.timeZone(e.timeZoneID)))
                                        .font(.system(size: 12.5)).opacity(0.65)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(app.palette.clay).accessibilityHidden(true)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if index > 0 { Rectangle().fill(app.palette.rule).frame(height: 1) } }
                        .accessibilityIdentifier("eventRecap.next.\(index)")
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

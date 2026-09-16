import Foundation
import Supabase

/// Row payloads for the writes this app makes. PostgREST needs `Encodable`
/// values, so each write gets a small explicit struct rather than an
/// untyped dictionary.
struct ProfilePreferenceUpdate: Encodable {
    let locale: String?
    let theme: String?
    let prefsSaved: Bool
    enum CodingKeys: String, CodingKey {
        case locale, theme
        case prefsSaved = "prefs_saved"
    }
}

/// Task 4 (migration 056) — same profiles.update() pattern as
/// ProfilePreferenceUpdate above, its own small struct since it's an
/// unrelated column.
struct AutoEmailDocumentsUpdate: Encodable {
    let autoEmailDocuments: Bool
    enum CodingKeys: String, CodingKey { case autoEmailDocuments = "auto_email_documents" }
}

/// Proof-of-consent (note 10 / migration 055) — written both from
/// applySession()'s auto-stamp below (an 'email'-provider session) and
/// from AppState.acceptPolicyGate() (a brand-new OAuth profile accepting
/// the mandatory Policy gate). File-scope, not nested, so both can share it.
struct ConsentUpdate: Encodable {
    let policyAcceptedAt: String
    let policyVersion: String
    enum CodingKeys: String, CodingKey {
        case policyAcceptedAt = "policy_accepted_at"
        case policyVersion = "policy_version"
    }
}

struct NewThread: Encodable {
    let eventId: String
    let guestId: UUID
    let organizerId: String
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case guestId = "guest_id"
        case organizerId = "organizer_id"
    }
}

struct NewMessage: Encodable {
    let threadId: UUID
    let senderId: UUID
    let body: String
    let kind: String
    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case senderId = "sender_id"
        case body, kind
    }
}

struct NotificationReadUpdate: Encodable {
    let readAt: String
    enum CodingKeys: String, CodingKey { case readAt = "read_at" }
}

// Decodable shapes for the handful of narrow selects below.
private struct IDRow: Decodable { let id: String }
private struct OrganizerRow: Decodable { let id: String; let name: String }
private struct UUIDRow: Decodable { let id: UUID }
private struct OrganizerRef: Decodable { let organizerId: String?
    enum CodingKeys: String, CodingKey { case organizerId = "organizer_id" } }
private struct BookingBrief: Decodable {
    let eventId: String
    let qty: Int
    let status: String
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case qty, status
    }
}
private struct AttendanceBooking: Decodable {
    let id: UUID
    let userId: UUID?
    let qty: Int
    let status: String
    let totalVnd: Int?
    let code: String?
    let expiresAt: Date?
    let paidMarkedAt: Date?
    let proofPath: String?
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case qty, status, code
        case totalVnd = "total_vnd"
        case expiresAt = "expires_at"
        case paidMarkedAt = "paid_marked_at"
        case proofPath = "proof_path"
    }
}
private struct ProfileName: Decodable {
    let id: UUID
    let displayName: String?
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}
private struct ThreadRow: Decodable {
    let id: UUID
    let eventId: String
    let guestId: UUID?
    let organizerId: String
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case guestId = "guest_id"
        case organizerId = "organizer_id"
    }
}
private struct MessageBrief: Decodable {
    let threadId: UUID
    let body: String
    let senderId: UUID?
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case body
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}
/// What the SECURITY DEFINER RPCs return — every one of them answers with
/// `{ success: bool, error?: string }` (or the booking row, for hold_seats).
private struct RPCResult: Decodable {
    let success: Bool?
    let error: String?
}

// MARK: - Session, profile and account data

extension AppState {

    /// Applies a signed-in session: loads the profile, role, saved
    /// preferences and this account's real bookings/organizer events —
    /// the same work syncUser() does on the web.
    func applySession(_ session: Session?) async {
        guard let session else {
            userID = nil
            userEmail = nil
            user = nil
            accountType = "participant"
            organizerMode = false
            hasHosted = false
            mode = "goer"
            attending = []
            tickets = [:]
            myOrgEventKeys = []
            orgRegName = ""
            notifications = []
            toasts = []
            stopNotificationPolling()
            booking = nil
            holdDeadline = nil
            return
        }
        userID = session.user.id
        userEmail = session.user.email

        do {
            let profile: Profile = try await SupabaseService.client
                .from("profiles").select().eq("id", value: session.user.id)
                .single().execute().value
            user = profile
            accountType = profile.role
            let canHostNow = profile.role == "organizer" || profile.role == "admin"
            organizerMode = canHostNow
            mode = canHostNow ? "host" : "goer"
            autoEmailDocuments = profile.autoEmailDocuments == true

            // Proof-of-consent bookkeeping (note 10 — this was a gap this
            // app never closed on any path before now, not just OAuth: see
            // that note's Task 1). For an 'email'-provider session
            // (password/emailed-code — LoginView.canRequest already
            // requires the tick before either ever runs), any profile with
            // no recorded consent yet just passed through that gate and
            // can be stamped unconditionally, same as GocContext.jsx's
            // syncUser(). An OAuth session is different: nothing gated it
            // client-side (signInWithGoogle()/signInWithFacebook() run with
            // no consent check at all — a returning user must be able to
            // tap straight through with zero friction), so a brand-new
            // profile here genuinely has never seen the policy. Route to a
            // mandatory, no-back-out Policy screen instead of trying to
            // verify intent before the fact (that used to check
            // `policyConsent` here and sign the session back out if it
            // wasn't set — fragile, since nothing actually required it to
            // be ticked before the button was ever tappable, and it
            // regressed note 09's Signup-only checkbox fix). Nothing
            // happens here for a *returning* OAuth sign-in — its profile
            // already has policyAcceptedAt — so it's exactly as
            // frictionless as password login.
            if profile.policyAcceptedAt == nil {
                let provider = session.user.appMetadata["provider"]?.stringValue
                if provider == nil || provider == "email" {
                    let update = ConsentUpdate(policyAcceptedAt: ISO8601DateFormatter().string(from: Date()), policyVersion: PolicyView.version)
                    do {
                        try await SupabaseService.client.from("profiles").update(update).eq("id", value: session.user.id).execute()
                    } catch {
                        print("Failed to record policy consent:", error)
                    }
                } else {
                    policyGateActive = true
                    screen = .policy
                    return
                }
            }

            // Language & theme follow the account once it has saved
            // preferences, so signing in on any device restores them.
            if profile.prefsSaved == true {
                lang = profile.locale == "en" ? "en" : "vi"
                theme = profile.theme == "dark" ? "dark" : "light"
            } else {
                persistPreference(["locale": lang, "theme": theme])
            }
        } catch {
            print("Profile load failed:", error)
        }

        await loadMyEvents()
        await loadNotifications()
        startNotificationPolling()
        requestPushAuthorizationIfNeeded()
        await loadBookingForCurrentEvent()
    }

    func signOut() async {
        try? await SupabaseService.client.auth.signOut()
        // Roles belong to the account that just left — leaving them behind
        // would leak the previous user's hosting state into the next sign-in.
        await applySession(nil)
        // Lands on Login, not Home — Task 1: no guest browsing after
        // signing out. authMandatory since there's nothing legitimate left
        // to go "back" to.
        screen = .login
        authMandatory = true
        authReturnScreen = .home
        authBackScreen = .home
    }

    /// Which catalogue events this account is actually attending (from real
    /// bookings) and which it organizes (from owning the organizer row).
    func loadMyEvents() async {
        guard let uid = userID else { return }
        do {
            let bookings: [BookingBrief] = try await SupabaseService.client
                .from("bookings")
                .select("event_id, qty, status")
                .eq("user_id", value: uid)
                .in("status", values: ["pending", "confirmed", "attended"])
                .execute().value
            var going: [String] = []
            var counts: [String: Int] = [:]
            for booking in bookings where !going.contains(booking.eventId) {
                going.append(booking.eventId)
                counts[booking.eventId] = booking.qty
            }
            attending = going
            tickets = counts

            let organizers: [OrganizerRow] = try await SupabaseService.client
                .from("organizers")
                .select("id, name")
                .or("owner_id.eq.\(uid.uuidString),user_id.eq.\(uid.uuidString)")
                .execute().value
            myOrganizerIDs = organizers.map(\.id)
            if !organizers.isEmpty {
                // The account's actual host page name — Account used to
                // always fall back to the generic "Bếp Nhỏ" placeholder
                // here, since this was the only place an organizer's name
                // could be restored on a fresh session and it was never
                // actually fetched.
                if let name = organizers.first?.name, !name.isEmpty { orgRegName = name }
                let events: [IDRow] = try await SupabaseService.client
                    .from("events")
                    .select("id")
                    .in("organizer_id", values: organizers.map(\.id))
                    .execute().value
                myOrgEventKeys = events.map(\.id)
                if !events.isEmpty { hasHosted = true }
            }
        } catch {
            print("Failed to load account events:", error)
        }
    }

    /// The signed-in user's latest booking for whichever event is open —
    /// drives the ticket bar, hold countdown and Confirmed screen.
    func loadBookingForCurrentEvent() async {
        guard let uid = userID else { booking = nil; holdDeadline = nil; return }
        do {
            let rows: [Booking] = try await SupabaseService.client
                .from("bookings").select()
                .eq("event_id", value: eventKey)
                .eq("user_id", value: uid)
                .order("created_at", ascending: false)
                .limit(1)
                .execute().value
            // Always set, even to nil — otherwise navigating from a booked
            // event to one you have no booking for keeps the stale ticket.
            booking = rows.first
            holdDeadline = rows.first?.expiresAt
        } catch {
            booking = nil
            holdDeadline = nil
        }
    }

    /// The real events row's own status/starts_at for whichever event is
    /// currently open — runs for every visitor, signed in or not, since
    /// "has this event ended/been cancelled" is public information. Every
    /// one of the 20 demo events also has a real row (seeded to match the
    /// catalogue's bundled cancelled/ended flags), so this resolves for
    /// those too; only a client-side-only preview has no row, and
    /// `applyingLiveStatus` leaves the bundled catalogue untouched then.
    func loadLiveEventStatus() async {
        do {
            let rows: [LiveEventStatus] = try await SupabaseService.client
                .from("events")
                .select("status, starts_at, cancelled_at, cancel_reason")
                .eq("id", value: eventKey)
                .limit(1)
                .execute().value
            liveEventStatus = rows.first
        } catch {
            liveEventStatus = nil
        }
    }

    // MARK: - Organizer mode

    func toggleOrganizerMode() {
        guard isSignedIn else { return requireAuth(returnTo: .profile, backTo: .profile) }
        let target = !canHost
        Task { await applyOrganizerMode(target) }
    }

    func applyOrganizerMode(_ enabled: Bool) async {
        guard accountType != "admin" else { return }
        let rollbackMode = organizerMode
        let rollbackType = accountType
        organizerMode = enabled
        accountType = enabled ? "organizer" : "participant"
        mode = enabled ? "host" : "goer"
        organizerModeError = ""
        if !enabled { hasHosted = false }

        do {
            let role: String = try await SupabaseService.client
                .rpc("set_organizer_mode", params: ["p_enabled": enabled])
                .execute().value
            accountType = role
            organizerMode = (role == "organizer" || role == "admin")
        } catch {
            // Rolling back in silence is what makes the switch look like it
            // "turns itself back off" — always say why it went back.
            organizerMode = rollbackMode
            accountType = rollbackType
            mode = rollbackMode ? "host" : "goer"
            organizerModeError = T(
                "Không thể đổi chế độ tổ chức lúc này. Vui lòng thử lại.",
                "We could not change organizer mode right now. Please try again."
            )
        }
    }

    // MARK: - Display name

    func goEditName() {
        editNameValue = user?.displayName ?? ""
        editNameError = ""
        screen = .editName
    }

    func saveDisplayName() async {
        let newName = editNameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            editNameError = T("Hãy nhập tên hiển thị.", "Please enter a display name.")
            return
        }
        if newName == user?.displayName { screen = .profile; return }
        editNameSaving = true
        editNameError = ""
        let oldName = user?.displayName ?? ""
        do {
            _ = try await SupabaseService.client
                .rpc("rename_display_name", params: ["p_new_name": newName])
                .execute()
            editNameSaving = false
            user?.displayName = newName
            screen = .profile
            // The in-app notifications are written by the RPC itself; this
            // only dispatches the email side, which re-derives its own
            // recipients server-side.
            await AuthAPIService.notify(
                path: "/api/notify",
                body: ["type": "name_change", "oldName": oldName, "newName": newName]
            )
        } catch {
            editNameSaving = false
            editNameError = T(
                "Không thể đổi tên lúc này. Vui lòng thử lại.",
                "We could not change your name right now. Please try again."
            )
        }
    }

    // MARK: - Notifications

    func goNotifications() {
        screen = .notifications
        Task { await loadNotifications() }
    }

    func loadNotifications() async {
        guard let uid = userID else { notifications = []; return }
        do {
            notifications = try await SupabaseService.client
                .from("notifications").select()
                .eq("recipient_id", value: uid)
                .order("created_at", ascending: false)
                .limit(50)
                .execute().value
        } catch {
            print("Failed to load notifications:", error)
        }
    }

    /// Refetches on a 5s poll (mirrors GocContext.jsx's own poll — no
    /// realtime subscription anywhere in this app, see
    /// .claude/notes/03-dispute-chat.md) and pushes a toast for any row
    /// created after this task started that hasn't been toasted yet.
    /// `sessionStart` is captured before the first request goes out, not
    /// derived from what that first request happens to return — a row
    /// inserted while it's still in flight has to toast, since the person
    /// genuinely hasn't seen it; diffing against "whatever came back last
    /// time" instead would silently swallow exactly that row (present on
    /// the very first poll, so treated as already-seen, never toasted).
    /// Started from applySession() on sign-in, stopped on sign-out.
    func startNotificationPolling() {
        notificationPollTask?.cancel()
        let sessionStart = Date()
        var toastedIDs = Set<UUID>()
        notificationPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let uid = self.userID else { return }
                do {
                    let rows: [AppNotification] = try await SupabaseService.client
                        .from("notifications").select()
                        .eq("recipient_id", value: uid)
                        .order("created_at", ascending: false)
                        .limit(50)
                        .execute().value
                    for row in rows where !toastedIDs.contains(row.id) && row.createdAt > sessionStart {
                        toastedIDs.insert(row.id)
                        self.pushToast(row)
                    }
                    self.notifications = rows
                } catch {
                    print("Notification poll failed:", error)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopNotificationPolling() {
        notificationPollTask?.cancel()
        notificationPollTask = nil
    }

    /// Marks one notification read — never all at once, and never merely
    /// from opening the list; read status has to follow an actual tap.
    func markNotificationRead(_ notification: AppNotification) async {
        guard notification.readAt == nil else { return }
        let readAt = Date()
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].readAt = readAt
        }
        let formatter = ISO8601DateFormatter()
        do {
            try await SupabaseService.client.from("notifications")
                .update(NotificationReadUpdate(readAt: formatter.string(from: readAt)))
                .eq("id", value: notification.id)
                .execute()
        } catch {
            print("Failed to mark notification read:", error)
        }
    }

    /// Tapping a notification marks it read and, for the kinds that point
    /// somewhere real, takes you there.
    func openNotification(_ notification: AppNotification) {
        Task { await markNotificationRead(notification) }
        switch notification.kind {
        case "new_message":
            if let threadID = notification.data["thread_id"]?.stringValue,
               let uuid = UUID(uuidString: threadID) {
                let key = notification.data["event_id"]?.stringValue ?? self.eventKey
                openThread(id: uuid, eventKey: key, back: .inbox)
            }
        case "booking_requested":
            // The organizer's side: straight to the check-in list for that
            // event, where "mark as paid" already lives (AttendanceView).
            if let key = notification.data["event_id"]?.stringValue {
                openAttendance(key)
            }
        case "payment_confirmed":
            if let bookingIDString = notification.data["booking_id"]?.stringValue,
               let bookingID = UUID(uuidString: bookingIDString) {
                let key = notification.data["event_id"]?.stringValue
                Task { await openBookingConfirmed(bookingID: bookingID, eventKey: key) }
            }
        case "dispute_message":
            // Only the guest and organizer ever receive this kind
            // (migrations 048/050 — admin is deliberately excluded), so
            // accountType alone decides which screen has this booking's
            // chat panel. message_id may be absent on a row from before
            // migration 050 — DisputeChatPanel.swift falls back to
            // scrolling to the bottom instead.
            if let bookingIDString = notification.data["booking_id"]?.stringValue,
               let bookingID = UUID(uuidString: bookingIDString) {
                let messageID = notification.data["message_id"]?.stringValue.flatMap(UUID.init(uuidString:))
                chatHighlight = (bookingID: bookingID, messageID: messageID)
                if accountType == "organizer" { openVerifications() } else { openPaymentDetails(bookingID) }
            }
        case "payment_document_uploaded", "payment_document_replaced":
            if let documentIDString = notification.data["document_id"]?.stringValue,
               let documentID = UUID(uuidString: documentIDString) {
                Task { await openDocumentFromNotification(documentID) }
            }
        default:
            break
        }
    }

    /// Deep-links a bell notification straight to the document it's about,
    /// without needing the full Documents list loaded first — fetches the
    /// one row RLS allows this account to see and opens the viewer on it.
    func openDocumentFromNotification(_ targetID: UUID) async {
        do {
            let doc: PaymentDocument = try await SupabaseService.client
                .from("payment_documents").select("*")
                .eq("id", value: targetID.uuidString)
                .single().execute().value
            documents = [doc]
            documentID = doc.id
            documentsKind = doc.kind
            documentsRole = "guest"
            screen = .documentView
            documentFileURL = nil
            if let path = doc.filePath, !path.isEmpty {
                documentFileURL = await signedDocumentFileURL(path)
            }
        } catch {
            print("openDocumentFromNotification failed:", error)
        }
    }

    /// A real, permanent delete — not audit-sensitive the way
    /// dispute_messages is (05-notify-retention.md's 72h retention is a
    /// different table entirely), so no soft-delete. RLS
    /// (notifications_delete_own, migration 050) already scopes this to
    /// the caller's own rows.
    func deleteNotification(_ notification: AppNotification) async {
        let previous = notifications
        notifications.removeAll { $0.id == notification.id }
        do {
            try await SupabaseService.client.from("notifications")
                .delete().eq("id", value: notification.id).execute()
        } catch {
            print("Failed to delete notification:", error)
            notifications = previous // put it back — the delete didn't actually happen
        }
    }

    /// Reopens the Confirmed/ticket screen for a specific booking — used
    /// when a 'payment_confirmed' notification is tapped after the guest has
    /// moved on elsewhere in the app, since the booking that just unlocked
    /// its QR code isn't necessarily the one still held in `booking`.
    func openBookingConfirmed(bookingID: UUID, eventKey: String?) async {
        do {
            let fresh: Booking = try await SupabaseService.client
                .from("bookings").select().eq("id", value: bookingID.uuidString)
                .single().execute().value
            booking = fresh
            self.eventKey = eventKey ?? fresh.eventId
            holdDeadline = fresh.expiresAt
            now = Date()
            screen = .confirmed
            await loadLiveEventStatus()
        } catch {
            print("openBookingConfirmed failed:", error)
        }
    }

    /// The client-side half of forfeiting a lapsed PHASE 1 hold. Called the
    /// instant a ticking countdown (ConfirmedView, PaymentDetailsView,
    /// HomeView's banner) notices its own deadline has passed while still
    /// 'holding'.
    ///
    /// Every screen that shows "Going"/a ticket/the Reserve-vs-ticket toggle
    /// reads this same booking's paymentState/status out of shared state —
    /// never off a live countdown — so patching them here is what makes all
    /// three update immediately, together, regardless of which screen
    /// actually noticed the expiry. The RPC call alongside it is what makes
    /// that true durably instead of just visually: without it, this booking
    /// would sit at status "confirmed" (instant-approval events set that
    /// immediately, before payment) until the next minutely sweep — or
    /// forever, had the sweep ever failed on it the way it once did for
    /// exactly this case.
    /// Called from PaymentDetailsView / HomeView, which hold this account's
    /// bookings as `PayableBooking` (the `bookings` + joined `events`/
    /// `organizers` shape `loadPaymentBookings()` fetches).
    func forfeitExpiredHold(_ payable: PayableBooking) {
        forfeitExpiredHoldCore(bookingID: payable.id, eventKey: payable.eventKey)
        if let index = paymentBookings.firstIndex(where: { $0.id == payable.id }) {
            paymentBookings[index].paymentState = .expired
            paymentBookings[index].status = "expired"
        }
    }

    /// Called from ConfirmedView, which holds the ticket's own booking as a
    /// plain `Booking` (whatever `submitReserve`/`openBookingConfirmed`/the
    /// polling refresh last fetched it as) rather than a `PayableBooking`.
    func forfeitExpiredHold(_ current: Booking) {
        forfeitExpiredHoldCore(bookingID: current.id, eventKey: current.eventId)
    }

    /// The client-side half of forfeiting a lapsed PHASE 1 hold, shared by
    /// both overloads above. Called the instant a ticking countdown
    /// (ConfirmedView, PaymentDetailsView, HomeView's banner) notices its own
    /// deadline has passed while still 'holding'.
    ///
    /// Every screen that shows "Going"/a ticket/the Reserve-vs-ticket toggle
    /// reads this same booking's paymentState/status out of shared state —
    /// never off a live countdown — so patching them here is what makes all
    /// three update immediately, together, regardless of which screen
    /// actually noticed the expiry. The RPC call alongside it is what makes
    /// that true durably instead of just visually: without it, this booking
    /// would sit at status "confirmed" (instant-approval events set that
    /// immediately, before payment) until the next minutely sweep — or
    /// forever, had the sweep ever failed on it the way it once did for
    /// exactly this case.
    private func forfeitExpiredHoldCore(bookingID: UUID, eventKey: String) {
        attending.removeAll { $0 == eventKey }
        if let current = booking, current.id == bookingID {
            var updated = current
            updated.paymentState = .expired
            updated.status = "expired"
            self.booking = updated
        }
        Task {
            do {
                let result: ForfeitResult = try await SupabaseService.client
                    .rpc("forfeit_my_expired_hold", params: ["p_booking": bookingID.uuidString])
                    .execute().value
                if result.success == false {
                    print("forfeitExpiredHold RPC declined:", result.error ?? "unknown")
                }
            } catch {
                print("forfeitExpiredHold RPC failed:", error)
            }
        }
    }

    // MARK: - Reserve / booking

    func qtyMinus() { qty = max(1, qty - 1) }
    func qtyPlus() { qty = min(6, qty + 1) }

    func submitReserve() async {
        loading = true
        reserveError = ""
        do {
            // hold_seats() (migration 026), not the legacy claim_seats() —
            // the latter never touches payment_state/hold_expires_at, so
            // every booking it created sat at the column default
            // (payment_state = 'holding', hold_expires_at = NULL) forever,
            // which is what left the ticket screen showing "Holding your
            // spot"/00:00 permanently regardless of the event's real state.
            let created: Booking = try await SupabaseService.client
                .rpc("hold_seats", params: HoldSeatsParams(event: eventKey, qty: qty))
                .execute().value
            booking = created
            holdDeadline = created.holdExpiresAt
            now = Date()
            tickets[eventKey] = qty
            if !attending.contains(eventKey) { attending.append(eventKey) }
            loading = false
            screen = .confirmed
        } catch {
            loading = false
            reserveError = T(
                "Không thể giữ chỗ lúc này. Vui lòng thử lại.",
                "Could not hold this spot right now. Please try again."
            )
        }
    }

    func addToCalendar() { calAdded = true }

    // MARK: - Chat

    func goChat() { Task { await openChat(for: eventKey, back: .organizer) } }

    /// Get-or-create the one thread between this guest and the event's
    /// organizer. Never used for the organizer's own side — that always
    /// opens a specific known thread (see openThread, used from Inbox).
    func openChat(for key: String, back: Screen) async {
        guard let uid = userID else { return requireAuth(returnTo: .chat, backTo: .organizer) }
        eventKey = key
        chatBack = back
        chatThreadID = nil
        chatMessages = []
        screen = .chat

        do {
            let existing: [UUIDRow] = try await SupabaseService.client
                .from("threads").select("id")
                .eq("event_id", value: key)
                .eq("guest_id", value: uid)
                .limit(1)
                .execute().value
            if let found = existing.first {
                chatThreadID = found.id
                await loadChatMessages(found.id)
                return
            }
            let events: [OrganizerRef] = try await SupabaseService.client
                .from("events").select("organizer_id")
                .eq("id", value: key)
                .limit(1)
                .execute().value
            guard let organizerID = events.first?.organizerId else { return }
            let created: [UUIDRow] = try await SupabaseService.client
                .from("threads")
                .insert(NewThread(eventId: key, guestId: uid, organizerId: organizerID))
                .select("id")
                .execute().value
            if let thread = created.first {
                chatThreadID = thread.id
                await loadChatMessages(thread.id)
            }
        } catch {
            print("Could not open conversation:", error)
        }
    }

    func openThread(id: UUID, eventKey: String, back: Screen) {
        self.eventKey = eventKey
        chatBack = back
        chatThreadID = id
        chatMessages = []
        screen = .chat
        Task { await loadChatMessages(id) }
    }

    func loadChatMessages(_ threadID: UUID) async {
        do {
            chatMessages = try await SupabaseService.client
                .from("messages")
                .select("id, thread_id, sender_id, body, kind, created_at, read_at")
                .eq("thread_id", value: threadID)
                .order("created_at", ascending: true)
                .execute().value
        } catch {
            print("Failed to load messages:", error)
        }
    }

    func chatSend() async {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let threadID = chatThreadID, let uid = userID else { return }
        chatDraft = ""
        do {
            let sent: [ChatMessage] = try await SupabaseService.client
                .from("messages")
                .insert(NewMessage(threadId: threadID, senderId: uid, body: text, kind: "text"))
                .select("id, thread_id, sender_id, body, kind, created_at, read_at")
                .execute().value
            if let message = sent.first { chatMessages.append(message) }
            // No email here — the notify_new_message trigger's in-app
            // notification is the only one a message gets, and tapping it
            // opens this same thread.
        } catch {
            print("Failed to send message:", error)
            chatDraft = text
        }
    }

    func chatBackAction() { screen = chatBack == .inbox ? .inbox : .organizer }

    /// A real, permanent delete, own messages only — RLS
    /// (messages_delete_own, migration 054) scopes this to
    /// `sender_id = auth.uid()`, which a system message (sender_id nil)
    /// can never match. No documented retention requirement for this
    /// table (unlike dispute_messages, see 05-notify-retention.md), so no
    /// soft-delete here either.
    func deleteMessage(_ id: UUID) async {
        let previous = chatMessages
        chatMessages.removeAll { $0.id == id }
        do {
            try await SupabaseService.client.from("messages").delete().eq("id", value: id).execute()
        } catch {
            print("Failed to delete message:", error)
            chatMessages = previous // put it back — the delete didn't actually happen
        }
    }

    /// Conversations on both sides: as the guest, and as the organizer of
    /// threads belonging to an organizer this account owns.
    func loadInboxThreads() async {
        guard let uid = userID else { inboxThreads = []; return }
        do {
            let asGuest: [ThreadRow] = try await SupabaseService.client
                .from("threads").select("id, event_id, guest_id, organizer_id")
                .eq("guest_id", value: uid)
                .execute().value

            let myOrgs: [IDRow] = try await SupabaseService.client
                .from("organizers").select("id")
                .or("owner_id.eq.\(uid.uuidString),user_id.eq.\(uid.uuidString)")
                .execute().value

            var asHost: [ThreadRow] = []
            if !myOrgs.isEmpty {
                asHost = try await SupabaseService.client
                    .from("threads").select("id, event_id, guest_id, organizer_id")
                    .in("organizer_id", values: myOrgs.map(\.id))
                    .execute().value
            }

            var seen = Set<UUID>()
            let threads = (asGuest + asHost).filter { seen.insert($0.id).inserted }
            guard !threads.isEmpty else { inboxThreads = []; return }

            let messages: [MessageBrief] = try await SupabaseService.client
                .from("messages").select("thread_id, body, sender_id, created_at")
                .in("thread_id", values: threads.map(\.id))
                .order("created_at", ascending: false)
                .execute().value
            var lastByThread: [UUID: MessageBrief] = [:]
            for message in messages where lastByThread[message.threadId] == nil {
                lastByThread[message.threadId] = message
            }

            let guestIDs = Array(Set(threads.compactMap { $0.guestId != uid ? $0.guestId : nil }))
            var guestNames: [UUID: String] = [:]
            if !guestIDs.isEmpty {
                let profiles: [ProfileName] = try await SupabaseService.client
                    .from("profiles").select("id, display_name")
                    .in("id", values: guestIDs.map(\.uuidString))
                    .execute().value
                for profile in profiles { guestNames[profile.id] = profile.displayName }
            }

            inboxThreads = threads.compactMap { thread -> InboxThread? in
                guard let event = EventCatalog.find(thread.eventId) else { return nil }
                let last = lastByThread[thread.id]
                let iAmGuest = thread.guestId == uid
                let name: String
                if iAmGuest {
                    name = event.orgName
                } else {
                    let guestName = (guestNames[thread.guestId ?? UUID()] ?? "").trimmingCharacters(in: .whitespaces)
                    name = guestName.isEmpty ? "Khách" : guestName
                }
                let prefix = last?.senderId == uid ? "Bạn: " : ""
                return InboxThread(
                    id: thread.id,
                    eventKey: thread.eventId,
                    name: name,
                    img: event.img,
                    snippet: last.map { prefix + $0.body } ?? "",
                    lastAt: last?.createdAt
                )
            }.sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
        } catch {
            print("Failed to load conversations:", error)
        }
    }

    // MARK: - Attendance / check-in

    func openAttendance(_ key: String) {
        attendanceEventKey = key
        attendanceGuests = []
        screen = .attendance
        Task { await loadAttendanceGuests(key) }
    }

    func loadAttendanceGuests(_ key: String) async {
        attendanceLoading = true
        do {
            let bookings: [AttendanceBooking] = try await SupabaseService.client
                .from("bookings")
                .select("id, user_id, qty, status, total_vnd, code, expires_at, paid_marked_at, proof_path")
                .eq("event_id", value: key)
                .in("status", values: ["pending", "confirmed", "attended"])
                .execute().value
            let userIDs = Array(Set(bookings.compactMap(\.userId)))
            var names: [UUID: String] = [:]
            if !userIDs.isEmpty {
                let profiles: [ProfileName] = try await SupabaseService.client
                    .from("profiles").select("id, display_name")
                    .in("id", values: userIDs.map(\.uuidString))
                    .execute().value
                for profile in profiles { names[profile.id] = profile.displayName }
            }
            let rightNow = Date()
            attendanceGuests = bookings
                // Expired holds are seats nobody actually has — listing them
                // would just fill the check-in screen with ghosts.
                .filter { $0.status != "pending" || ($0.expiresAt ?? .distantFuture) > rightNow }
                .map { booking in
                    let raw = (names[booking.userId ?? UUID()] ?? "").trimmingCharacters(in: .whitespaces)
                    return AttendanceGuest(
                        id: booking.id,
                        name: raw.isEmpty ? "Khách" : raw,
                        qty: booking.qty,
                        checkedIn: booking.status == "attended",
                        paid: booking.paidMarkedAt != nil,
                        totalVnd: booking.totalVnd ?? 0,
                        code: booking.code ?? "",
                        hasProof: !(booking.proofPath ?? "").isEmpty
                    )
                }
            attendanceLoading = false
        } catch {
            print("Failed to load attendance list:", error)
            attendanceGuests = []
            attendanceLoading = false
        }
    }

    /// Tapping a guest checks them in; tapping one already checked in asks
    /// for a reason first (reversing is never silent — see ReasonSheet).
    func toggleCheckIn(_ guest: AttendanceGuest) {
        if guest.checkedIn {
            reasonPrompt = ReasonPrompt(kind: .undoCheckin, bookingID: guest.id, guestName: guest.name)
            reasonPromptError = ""
            return
        }
        if let index = attendanceGuests.firstIndex(where: { $0.id == guest.id }) {
            attendanceGuests[index].checkedIn = true
        }
        Task {
            let ok = await checkIn(bookingID: guest.id)
            if !ok, let index = attendanceGuests.firstIndex(where: { $0.id == guest.id }) {
                attendanceGuests[index].checkedIn = false
            }
        }
    }

    /// Both the manual list and the QR scanner go through this same
    /// already-authorized RPC, so they share one notification path.
    @discardableResult
    func checkIn(bookingID: UUID) async -> Bool {
        do {
            let result: RPCResult = try await SupabaseService.client
                .rpc("check_in_guest", params: ["p_reservation_id": bookingID.uuidString])
                .execute().value
            guard result.success == true else { return false }
            await AuthAPIService.notify(path: "/api/notify", body: ["type": "check_in", "bookingId": bookingID.uuidString])
            return true
        } catch {
            print("Check-in failed:", error)
            return false
        }
    }

    func checkInByScan(_ bookingID: String) async -> Bool {
        guard let uuid = UUID(uuidString: bookingID) else { return false }
        let ok = await checkIn(bookingID: uuid)
        if ok, let key = attendanceEventKey { await loadAttendanceGuests(key) }
        return ok
    }

    func openCancelBooking(_ guest: AttendanceGuest) {
        reasonPrompt = ReasonPrompt(kind: .cancelBooking, bookingID: guest.id, guestName: guest.name)
        reasonPromptError = ""
    }

    func closeReasonPrompt() {
        reasonPrompt = nil
        reasonPromptError = ""
    }

    /// Reversing a check-in or cancelling a paid booking always carries one
    /// of the fixed reasons, so the guest's notification says something
    /// concrete — and both are emailed as well as shown in-app.
    func submitReason(_ label: String) async {
        guard let prompt = reasonPrompt else { return }
        reasonPromptBusy = true
        reasonPromptError = ""
        do {
            let result: RPCResult
            switch prompt.kind {
            case .undoCheckin:
                result = try await SupabaseService.client
                    .rpc("undo_check_in", params: [
                        "p_booking_id": prompt.bookingID.uuidString, "p_reason": label,
                    ])
                    .execute().value
            case .cancelBooking:
                result = try await SupabaseService.client
                    .rpc("cancel_booking", params: [
                        "p_booking": prompt.bookingID.uuidString, "p_reason": label,
                    ])
                    .execute().value
            }
            guard result.success == true else { throw AuthAPIError(code: "RPC_FAILED") }

            reasonPrompt = nil
            reasonPromptBusy = false
            if let key = attendanceEventKey { await loadAttendanceGuests(key) }
            await AuthAPIService.notify(
                path: "/api/notify",
                body: [
                    "type": prompt.kind == .undoCheckin ? "checkin_undo" : "booking_cancelled",
                    "bookingId": prompt.bookingID.uuidString, "reason": label,
                ]
            )
        } catch {
            reasonPromptBusy = false
            reasonPromptError = prompt.kind == .undoCheckin
                ? T("Không thể huỷ điểm danh. Vui lòng thử lại.", "Could not undo the check-in. Please try again.")
                : T("Không thể huỷ vé. Vui lòng thử lại.", "Could not cancel the booking. Please try again.")
        }
    }

    // MARK: - Create event

    func pickCreateCategory(_ key: String) {
        if let index = createCats.firstIndex(of: key) {
            createCats.remove(at: index)
        } else {
            createCats.append(key)
            if createCats.count > 2 { createCats = [createCats[0], key] }
        }
    }

    func submitCreateEvent() async {
        guard !createName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading = true
        createError = ""
        if !canHost { await applyOrganizerMode(true) }

        let priceDigits = createPrice.filter { $0.isNumber }
        let capacity = Int(createSeats.filter { $0.isNumber }) ?? 0
        var eventDate: String?
        var eventTime: String?
        if let match = createDate.range(of: "(\\d{1,2})\\.(\\d{1,2})", options: .regularExpression) {
            let parts = createDate[match].split(separator: ".")
            if parts.count == 2, let day = Int(parts[0]), let month = Int(parts[1]) {
                eventDate = String(format: "2026-%02d-%02d", month, day)
            }
        }
        if let match = createDate.range(of: "(\\d{1,2}):(\\d{2})", options: .regularExpression) {
            eventTime = String(createDate[match])
        }

        do {
            _ = try await SupabaseService.client
                .rpc("create_event_draft", params: CreateEventParams(
                    name: createName.trimmingCharacters(in: .whitespaces),
                    category: createCats.first ?? "supper",
                    description: createDesc.trimmingCharacters(in: .whitespaces),
                    location: createLoc.trimmingCharacters(in: .whitespaces),
                    eventDate: eventDate,
                    eventTime: eventTime,
                    priceVnd: Int(priceDigits) ?? 0,
                    capacity: capacity,
                    organizerName: orgRegName.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Organizer" : orgRegName.trimmingCharacters(in: .whitespaces),
                    instagram: orgRegIg.trimmingCharacters(in: .whitespaces),
                    about: orgRegDesc.trimmingCharacters(in: .whitespaces)
                ))
                .execute()
            loading = false
            createSent = true
            hasHosted = true
            mode = "host"
            await loadMyEvents()
        } catch {
            loading = false
            createError = T(
                "Không thể gửi sự kiện lúc này. Vui lòng thử lại.",
                "Could not submit this event right now. Please try again."
            )
        }
    }

    func requestVerify() { orgVerifyRequested = true }
}

/// RPC parameter payloads (PostgREST needs one Encodable value per call;
/// mixed-type dictionaries aren't expressible in Swift).
struct HoldSeatsParams: Encodable {
    let event: String
    let qty: Int
    enum CodingKeys: String, CodingKey {
        case event = "p_event"
        case qty = "p_qty"
    }
}

struct CreateEventParams: Encodable {
    let name: String
    let category: String
    let description: String
    let location: String
    let eventDate: String?
    let eventTime: String?
    let priceVnd: Int
    let capacity: Int
    let organizerName: String
    let instagram: String
    let about: String

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case category = "p_category"
        case description = "p_description"
        case location = "p_location"
        case eventDate = "p_event_date"
        case eventTime = "p_event_time"
        case priceVnd = "p_price_vnd"
        case capacity = "p_capacity"
        case organizerName = "p_organizer_name"
        case instagram = "p_instagram"
        case about = "p_about"
    }
}

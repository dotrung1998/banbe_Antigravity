import SwiftUI
import UIKit

/// Port of src/screens/Inbox.jsx — every conversation this account is in,
/// on either side (as guest, and as organizer of their own events).
///
/// 2026-09-21 follow-up: switched from a plain ScrollView/VStack to a
/// `List` (kept since — see the ScaffoldScrollProbe usage below for why).
///
/// Row-swipe-vs-tab-swipe fix pass (2026-09-28, third follow-up) — rows no
/// longer use `.swipeActions` for Star/Archive; see `InboxRow`'s own doc
/// comment for why, and for the tap-only "…" menu that replaced it.
struct InboxView: View {
    @EnvironmentObject var app: AppState
    // TASK 2 (2026-09-22 twenty-first follow-up) — Archived isn't its own
    // `Screen` case, it's `app.inboxView` (.active/.archived) toggled
    // WITHIN this same `.inbox` screen (see AppState.swift's
    // `InboxViewMode`). RootView's interactive edge-swipe peek renders
    // `screenView(for: app.backTargetScreen, isPreview: true)` — for
    // Archived, `backTargetScreen` correctly resolves to `.inbox`
    // (AppState.swift ~line 1678), but that peek is a FRESH `InboxView()`
    // reading the SAME live `app.inboxView`, which is still `.archived`
    // (the peek is non-interactive and never changes it) — so the "back
    // target" preview showed Archived again, duplicated, instead of the
    // actual destination (active Inbox). `isPreview` forces the preview
    // copy specifically to `.active`, since swiping back FROM Archived (or
    // from anywhere else whose back target is Inbox) always means "the
    // active thread list", never Archived itself.
    var isPreview: Bool = false
    @State private var searchOpen = false
    @State private var query = ""
    @State private var feedbackOpen = false
    // Bug 1c (2026-09-21 follow-up) — brings up the keyboard the instant
    // the search field appears, no extra tap needed first.
    @FocusState private var searchFieldFocused: Bool

    // Bug 1b/1c (2026-09-21 follow-up) — a noticeably slower spring for the
    // search field's reveal than a default SwiftUI animation.
    private static let sheetAnimation = Animation.spring(response: 0.6, dampingFraction: 0.85)

    private var effectiveInboxView: InboxViewMode { isPreview ? .active : app.inboxView }

    private var visibleThreads: [InboxThread] {
        let byView = app.inboxThreads.filter { t in
            let archived = app.inboxThreadPrefs[t.id]?.archived ?? false
            return effectiveInboxView == .archived ? archived : !archived
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return byView }
        return byView.filter { $0.name.lowercased().contains(q) || $0.snippet.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                // Loading-icon-position fix pass — `RootRefreshIndicator`
                // used to be a sibling of this WHOLE `VStack` (header
                // included), overlaid top-aligned against the FULL screen
                // with a flat `.padding(.top, 54)` — measured from the top
                // of the SCREEN, behind/above where `header` itself sits.
                // Home/Notifications place the exact same indicator via
                // `ScreenScaffold`'s own `refreshIndicatorTopPadding: 16`,
                // but that padding is measured from the top of THEIR
                // scroll content, which is already below their own header
                // (a sibling above `ScreenScaffold`, same shape as `header`
                // here) — so their "16" and this view's old "54" were never
                // comparable numbers, and 54 measured from the screen top
                // landed the spinner far too close to (and this view's
                // taller header could even visually sit AT) this header's
                // own bottom edge. Scoping this ZStack to the content BELOW
                // `header` — the same reference frame `refreshIndicatorTopPadding`
                // already uses — and reusing that exact established `16`
                // value fixes it without touching `header` or the pull/
                // refresh mechanics below.
                ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                if effectiveInboxView == .archived {
                    Button("‹ " + app.T("Quay lại Tin nhắn", "Back to Messages")) { app.inboxView = .active }
                        .font(.system(size: 12.5)).buttonStyle(.plain)
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.horizontal, 24).padding(.bottom, 6)
                }
                // No standalone dispute band above the conversation list any
                // more. A refund dispute now lives INSIDE the booking
                // conversation it belongs to, as a block hung off that
                // conversation's own "Booking cancelled" system card (and an
                // escalated payment dispute off its own matching card), so
                // there is exactly one conversation per booking instead of a
                // second, parallel list of the same arguments sitting above
                // the real ones. What's left of that idea is the highlight
                // below: the conversation carrying a live dispute is marked
                // on its own row, so it's still findable from here.
                if visibleThreads.isEmpty {
                    Text(effectiveInboxView == .archived
                         ? app.T("Chưa có cuộc trò chuyện nào được lưu trữ.", "No archived conversations yet.")
                         : app.T("Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.", "No conversations yet. Message an organizer from an event page."))
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 80)
                        .foregroundStyle(app.palette.ink)
                    Spacer()
                } else {
                    List {
                        ForEach(visibleThreads) { thread in
                            InboxRow(thread: thread)
                                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                                .listRowSeparatorTint(app.palette.rule)
                                .listRowBackground(app.palette.paper)
                                // Refresh-indicator fix pass (2026-09-27,
                                // follow-up A) — same `ScaffoldScrollProbe`
                                // ScreenScaffold uses, anchored to this
                                // FIRST row (a real UITableView cell, so
                                // walking up from here reliably finds the
                                // List's own underlying UIScrollView —
                                // attaching it to the List itself does
                                // not, since `.background()` there sits
                                // outside that hierarchy) instead of the
                                // plain `.refreshable{}` this used to have
                                // (its system spinner can't be reskinned —
                                // see RootRefreshIndicator's own comment).
                                .background(
                                    thread.id == visibleThreads.first?.id && !isPreview
                                        ? AnyView(ScaffoldScrollProbe(
                                            onChange: { _ in },
                                            onPullPhase: { phase, translationY in
                                                switch phase {
                                                case .began: app.beginRootPull()
                                                case .changed: app.updateRootPull(translationY)
                                                case .ended: app.endRootPull(trigger: { await app.loadInboxThreads() })
                                                case .cancelled: app.cancelRootPull()
                                                }
                                            }
                                          ))
                                        : AnyView(EmptyView())
                                )
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(app.palette.paper)
                    // Pull-to-refresh hold fix (2026-09-29) — see
                    // `AppState.rootPullContentOffset`'s own doc comment.
                    .offset(y: app.rootPullContentOffset)
                }
                }
                if app.rootPullProgress > 0 || app.rootRefreshing {
                    RootRefreshIndicator(screen: .inbox, progress: app.rootPullProgress, refreshing: app.rootRefreshing)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                }
            }
        }
        .task { await app.loadInboxThreads() }
        // The dispute index is what marks which of these rows is carrying a
        // live dispute (see InboxRow). Nothing else on this screen needs it,
        // but it still has to be kept fresh here — the removed yellow
        // accordion used to own this poll, and it has to survive its removal.
        .task(id: effectiveInboxView) {
            guard effectiveInboxView == .active else { return }
            await app.loadDisputeChats()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                await app.loadDisputeChats()
            }
        }
        .fullScreenCover(isPresented: $feedbackOpen) { FeedbackFlowView() }
        // Bug 2a (2026-09-21 follow-up) — `FeedbackFlowView` is a hand-
        // rolled `.fullScreenCover` INSIDE the main window, but
        // BottomTabBarOverlay is a genuinely separate, always-on-top
        // `UIWindow` (see that file's own doc comment) that `.inbox`
        // staying in `visibleScreens` never hides on its own for a
        // same-screen presentation. Reuses the exact `isHidden`-sync
        // mechanism 4d549f9 already established for Event Detail
        // (`updateVisibility(for:)`), via `setForcedHidden(_:)`.
        //
        // Messaging-settings-menu fix pass (2026-09-28) — the settings
        // sheet's own half of this (`open || settingsOpen`) is gone along
        // with `settingsSheet` itself: a native `Menu` (see `header`
        // below) presents above everything on its own, exactly like
        // `InboxRow`'s "…" menu and `NotificationsView`'s row menu already
        // do, so there's nothing left here for the dock overlay to hide.
        .onChange(of: feedbackOpen) { _, open in BottomTabBarOverlay.shared.setForcedHidden(open) }
        .onDisappear {
            BottomTabBarOverlay.shared.setForcedHidden(false)
            app.cancelRootPull()
        }
    }

    // Task 1 — "Done" replaced with search + settings icons. Task 5 — each
    // icon-only control gets a small label underneath.
    private var header: some View {
        HStack(alignment: .center) {
            // "banbe" wordmark parity fix (2026-09-29, follow-up: placed
            // BEFORE the title, inline in the same row — not as its own
            // row above it) — matches Home's own header wordmark
            // (HomeView.swift). Hidden while the search field is showing.
            if !searchOpen {
                BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
            }
            if searchOpen {
                TextField(app.T("Tìm cuộc trò chuyện…", "Search conversations…"), text: $query)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(app.palette.field, in: Capsule())
                    .foregroundStyle(app.palette.ink)
                    .focused($searchFieldFocused)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text(effectiveInboxView == .archived ? app.T("Đã lưu trữ", "Archived") : app.T("Tin nhắn", "Messages"))
                    .font(BanbeTheme.display(27))
            }
            Spacer()
            HStack(spacing: 14) {
                // Bug 1c (2026-09-21 follow-up) — `searchFieldFocused` set
                // true right alongside the reveal animation so the
                // keyboard comes up immediately, not on a second tap.
                iconButton(searchOpen ? "xmark" : "magnifyingglass", label: searchOpen ? app.T("Đóng", "Close") : app.T("Tìm", "Search")) {
                    if searchOpen { query = "" }
                    withAnimation(Self.sheetAnimation) { searchOpen.toggle() }
                    searchFieldFocused = searchOpen
                }
                .accessibilityIdentifier("inbox.searchToggle")
                if effectiveInboxView == .active {
                    // Messaging-settings-menu fix pass (2026-09-28) — was a
                    // gearshape button opening a hand-rolled dim-overlay +
                    // sliding-panel sheet (`settingsSheet`, removed). Now a
                    // native `Menu`, the same tap-only pattern `InboxRow`'s
                    // "…" (Star/Archive) and `NotificationsView`'s row menu
                    // already use — one consistent way this app displays a
                    // short options list, instead of a third, bespoke one
                    // just for this one entry point.
                    Menu {
                        Button {
                            app.inboxView = .archived
                        } label: {
                            Label(app.T("Đã lưu trữ", "Archived"), systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("inbox.settings.archived")
                        Button {
                            feedbackOpen = true
                        } label: {
                            Label(app.T("Gửi phản hồi", "Give feedback"), systemImage: "bubble.left")
                        }
                        .accessibilityIdentifier("inbox.settings.feedback")
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .frame(width: 34, height: 34)
                                .background(app.palette.field, in: Circle())
                            Text(app.T("Cài đặt", "Settings")).font(.system(size: 9.5)).opacity(0.7)
                        }
                    }
                    .foregroundStyle(app.palette.ink)
                    .accessibilityIdentifier("inbox.settingsToggle")
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 34, height: 34)
                    .background(app.palette.field, in: Circle())
                Text(label).font(.system(size: 9.5)).opacity(0.7)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
    }

}

// The former standalone yellow "Disputes / Temporary" accordion that used to
// be pinned above these rows is gone on purpose: a dispute is not a separate
// conversation, it is an argument ABOUT one, so it now renders inside the
// booking conversation it belongs to (ChatView) as a block on that
// conversation's own system card. Everything a reader still needs from this
// list is carried by the "Dispute in progress" highlight on InboxRow below,
// which is driven by the same verified per-conversation data.

private struct InboxRow: View {
    @EnvironmentObject var app: AppState
    let thread: InboxThread

    // Task 3 (2026-09-21 follow-up) — bolds unread rows using the SAME
    // `thread.unread` signal loadInboxThreads() computes for the dock
    // badge, not a second computation.
    private var unread: Bool { thread.unread }
    private var starred: Bool { app.inboxThreadPrefs[thread.id]?.starred ?? false }

    /// This exact conversation is carrying a live dispute right now. Exact
    /// thread-id match against the dispute index (threads is
    /// UNIQUE(event_id, guest_id), so a conversation is a 1:1 identity) —
    /// never an event-name comparison, which would light up a second guest's
    /// conversation on the same event. Once the dispute is closed the row
    /// goes straight back to its normal styling.
    private var hasActiveDispute: Bool {
        app.activeDisputeConversationThreadIds.contains(thread.id)
    }

    var body: some View {
        // Row-swipe-vs-tab-swipe fix pass (2026-09-28, third follow-up) —
        // real, final fix: `.swipeActions` was abandoned entirely, not
        // patched a third time. Two independent attempts (a named
        // coordinate space, then moving the measuring `GeometryReader` off
        // `.listRowBackground`) each fixed a real, confirmed bug in the
        // row-vs-tab-swipe detection, and it STILL reproduced on-device,
        // every row, every time — meaning the underlying approach itself
        // (an ancestor `.simultaneousGesture` trying to out-guess a `List`
        // row's own UIKit swipe-actions recognizer purely from SwiftUI,
        // with no `UIGestureRecognizer.require(toFail:)`-level control
        // available from pure SwiftUI) can't be made reliable here. Star/
        // Archive now live behind an explicit tap target (the "…" button
        // below) instead of a swipe gesture — a `Menu`/`Button` tap never
        // competes with `RootView.tabSwipeGesture` at all (taps and drags
        // are different gesture classes; there's nothing left to
        // arbitrate), so this entire class of bug cannot recur here by
        // construction, not by another detection heuristic.
        //
        // Active-dispute tint (2026-10-04 fix) — the pale-red field used
        // to sit on the CENTRAL `HStack` only (`.background(alignment:
        // .leading)` below), so the avatar's left edge and the trailing
        // "…" menu stayed on the plain row colour while the middle read
        // highlighted. It now lives on this OUTER container instead — the
        // full row, with the List's own side insets respected — so avatar,
        // text and menu all sit inside one tinted, rounded surface with
        // consistent internal padding. The tint is a plain overlay, so it
        // never intercepts taps: the row-open `SwipeSafeButton` and the
        // sibling "…" `Menu` keep their exact hit targets, and closing the
        // dispute restores the row byte-for-byte.
        HStack(spacing: 4) {
            // Accidental-tap-during-navigation fix (2026-09-29) — a
            // SEPARATE issue from the row-swipe-actions-vs-tab-swipe
            // conflict this file's own comment above already solved: a
            // deliberate tap/swipe that navigated TO Inbox could leave the
            // finger resting on/near this first row the instant the
            // screen arrives, and a plain `Button` only checks "did
            // release land inside my bounds," not travel distance — see
            // `SwipeSafeButton`'s own doc comment (Components.swift).
            SwipeSafeButton { app.openThread(id: thread.id, eventKey: thread.eventKey, back: .inbox, otherName: thread.name) } label: {
                HStack(spacing: 16) {
                    // Task 3a — merged avatar: a small badge circle for the
                    // OTHER participant's own photo, overlapping the event
                    // photo's corner — mirrors src/screens/Inbox.jsx.
                    ZStack(alignment: .bottomTrailing) {
                        CatalogPhoto(path: thread.img, height: 56, width: 56, cornerRadius: 28)
                        Group {
                            if let url = thread.otherAvatarURL, let imageURL = URL(string: url) {
                                AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                            } else {
                                Circle().fill(app.palette.ink)
                                    .overlay(
                                        Text(String(thread.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(app.palette.paper)
                                    )
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .overlay(Circle().stroke(app.palette.paper, lineWidth: 2))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if unread { Circle().fill(BanbeTheme.alert).frame(width: 7, height: 7) }
                            // Bug 3 (2026-09-21 follow-up) — a fully-read row's
                            // name stays bold (still reads as the row's title)
                            // but lighter-contrast than an unread row's, via
                            // opacity rather than dropping below the preview
                            // line's own weight underneath it.
                            Text(thread.name)
                                .font(BanbeTheme.display(18))
                                .fontWeight(.semibold)
                                .foregroundStyle(app.palette.ink.opacity(unread ? 1 : 0.6))
                        }
                        Text(thread.snippet)
                            .font(.system(size: 13, weight: unread ? .semibold : .regular))
                            .foregroundStyle(app.palette.ink.opacity(unread ? 1 : 0.72))
                            .lineLimit(1)
                        // A live dispute on THIS conversation, in the same red
                        // alert accent the dispute card itself uses, so the
                        // row and the card read as one thing. Disappears on
                        // closure along with every other trace of the dispute
                        // in the list.
                        if hasActiveDispute {
                            Text(app.T("Tranh chấp đang diễn ra", "Dispute in progress"))
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(BanbeTheme.alert)
                                .accessibilityIdentifier("inbox.thread.disputeInProgress")
                        }
                    }
                    Spacer(minLength: 0)
                    // Bug 1 (2026-09-21 follow-up) — moved off the avatar
                    // (where it collided with the merged-avatar badge) to the
                    // row's own far trailing edge instead.
                    if starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(BanbeTheme.alert)
                    }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.palette.ink)
            .accessibilityIdentifier("inbox.threadRow")

            // A SIBLING control, not nested inside the row-open `Button`
            // above (SwiftUI/UIKit don't give a nested button its own
            // independent tap target reliably) — tapping "…" opens Archive/
            // Star directly, replacing the old swipe-left affordance.
            Menu {
                let archived = app.inboxThreadPrefs[thread.id]?.archived ?? false
                Button {
                    Task { archived ? await app.unarchiveThread(thread.id) : await app.archiveThread(thread.id) }
                } label: {
                    Label(archived ? app.T("Bỏ lưu trữ", "Unarchive") : app.T("Lưu trữ", "Archive"), systemImage: archived ? "tray.and.arrow.up" : "archivebox")
                }
                .accessibilityIdentifier("inbox.thread.archive")
                Button {
                    Task { await app.toggleThreadStar(thread.id) }
                } label: {
                    Label(starred ? app.T("Bỏ đánh dấu", "Unstar") : app.T("Gắn sao", "Star"), systemImage: starred ? "star.fill" : "star")
                }
                .accessibilityIdentifier("inbox.thread.star")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.55))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("inbox.thread.moreButton")
            // Active-dispute tint (2026-10-04 fix) — on this OUTER row
            // container, so it spans avatar, text and the trailing menu in
            // one surface. The List's own 24pt side insets clip it to the
            // normal row width (never screen-edge-to-edge), and the row's
            // corner radius matches the other tinted cards in the app.
            // `.allowsHitTesting(false)` keeps it a pure paint layer: the
            // row-open button and the "…" Menu keep their own hit targets
            // exactly as before, and closing the dispute restores the row
            // byte-for-byte.
            .background(alignment: .center) {
                if hasActiveDispute {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BanbeTheme.alert.opacity(0.10))
                        .padding(.horizontal, 4).padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
            }
            // Screenshot Catalog (docs/demo-screenshots) — not unique per row
            // (every row shares it, matched via `.matching(identifier:)`), the
            // same convention `chat.attachment` already uses (MessagingViews.swift)
            // for "any one of these, whichever exists" lookups. "Unread thread
            // appearance" is captured off the list itself (whatever mix of
            // read/unread the account currently has), not a second identifier
            // per read-state — nested SwiftUI accessibility ids on a row this
            // deep have already proven unreliable to resolve precisely
            // elsewhere in this suite (see EventDetailOpenInMapUITests' own
            // comment on `map.selectedCard`).
            .accessibilityIdentifier("inbox.threadRow")
        }
    }
}

/// Task 1b — "Give feedback": single-choice screen -> text+bug-toggle
/// screen, matching the attached reference screenshots.
private struct FeedbackFlowView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0 // 0 = choice, 1 = detail
    @State private var text = ""
    @State private var isBug = false
    @State private var sending = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if step == 1 { step = 0 } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .foregroundStyle(app.palette.ink)

                if step == 0 {
                    Text(app.T("Gửi phản hồi", "Give feedback")).font(BanbeTheme.display(24)).padding(.top, 16)
                    Text(app.T(
                        "Hãy cho chúng tôi biết phản hồi của bạn là về điều gì. Chúng tôi đọc mọi phản hồi nhưng không thể trả lời từng người.",
                        "Please let us know what your feedback is about. We review all feedback but are unable to respond individually."
                    ))
                    .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 10)

                    HStack {
                        Text(app.T("Phản hồi chung về hộp thư", "General feedback about the inbox")).font(.system(size: 14))
                        Spacer()
                        ZStack {
                            Circle().stroke(app.palette.ink, lineWidth: 2).frame(width: 20, height: 20)
                            Circle().fill(app.palette.ink).frame(width: 10, height: 10)
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .bottom)
                    .padding(.top, 16)

                    Spacer()
                    Button(app.T("Tiếp", "Next")) { step = 1 }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(app.T("Kể cho chúng tôi nghe", "Tell us about it")).font(BanbeTheme.display(24)).padding(.top, 16)
                    Text(app.T("Chia sẻ trải nghiệm của bạn. Điều gì tốt? Điều gì có thể tốt hơn?", "Share your experience with us. What went well? What could have gone better?"))
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 10)

                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                        .padding(.top, 14)

                    HStack {
                        Text(app.T("Tôi đang báo lỗi", "I'm reporting a bug")).font(.system(size: 14))
                        Spacer()
                        Toggle("", isOn: $isBug).labelsHidden().toggleStyle(BanbeLiquidToggleStyle())
                    }
                    .padding(.top, 16)

                    Spacer()
                    HStack {
                        Button(app.T("Quay lại", "Back")) { step = 0 }
                            .font(.system(size: 13.5)).buttonStyle(.plain)
                        Spacer()
                        Button {
                            Task {
                                sending = true
                                _ = await app.submitFeedback(text, isBugReport: isBug)
                                sending = false
                                dismiss()
                            }
                        } label: {
                            Text(sending ? app.T("Đang gửi…", "Sending…") : app.T("Gửi", "Send"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                        .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty || sending ? 0.5 : 1)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

/// Port of src/screens/Chat.jsx — the real threads/messages conversation,
/// polled every few seconds while open (there's no realtime subscription on
/// the web side either).
struct ChatView: View {
    @EnvironmentObject var app: AppState
    @State private var pollTask: Task<Void, Never>?
    // Task 4 (2026-09-21 follow-up) — the composer's "+" attach flow. The
    // button, its two-option menu, both pickers and the re-encode all moved
    // into ChatAttachButton (ChatAttachmentFlow.swift) when the temporary
    // refund dispute composer needed the identical experience; only this
    // view's own upload + send lives here now.
    @State private var sendingAttachment = false
    // Task 5 (2026-09-22 twelfth follow-up) — driven by app.chatFocusComposer
    // (set true only for a typed reply sent from ChatPhotoViewerView, never
    // a one-tap quick reaction — see AppState+Data.swift's own comment).
    @FocusState private var composerFocused: Bool
    // A concluded dispute's transcript is collapsed back into its system card
    // and only reopened on request, until the purge sweep removes it.
    @State private var transcriptExpanded = false

    private var event: CatalogEvent { app.currentEvent }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(app.palette.rule)
                messages
                composer
            }
        }
        // Which dispute, if any, belongs to THIS conversation — resolved by
        // exact thread id on open, and re-resolved for a few seconds after so
        // a dispute raised on the other device appears without a manual
        // reload. A thread switch resets both it and the collapsed
        // transcript state, so nothing carries over between conversations.
        .task(id: app.chatThreadID) {
            guard let threadID = app.chatThreadID else {
                app.conversationRefundDispute = nil
                app.conversationPaymentDisputeBookingID = nil
                return
            }
            transcriptExpanded = false
            app.conversationRefundDispute = nil
            await app.loadConversationDispute(conversationThreadID: threadID)
            for _ in 0..<2 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                guard app.chatThreadID == threadID else { return }
                await app.loadConversationDispute(conversationThreadID: threadID)
            }
        }
        .onDisappear {
            app.conversationRefundDispute = nil
            app.conversationPaymentDisputeBookingID = nil
            app.expandedDisputeClaimId = nil
            app.disputeChatScrollTarget = nil
        }
        .onAppear {
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if let id = app.chatThreadID { await app.loadChatMessages(id) }
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
        .onChange(of: app.chatFocusComposer) { _, focus in
            guard focus else { return }
            composerFocused = true
            app.chatFocusComposer = false
        }
    }

    // Task 1 (07-notifications.md) — mirrors web's attachmentBoxSize()
    // (Chat.jsx) exactly. The implementation now lives in AttachmentBubble
    // (ChatAttachmentFlow.swift), shared with the temporary refund dispute
    // composer so a photo's preview box is identical in both chats; this
    // forwarder keeps the existing call sites (and any test) working.
    static func attachmentBoxSize(width: Int?, height: Int?) -> CGSize {
        AttachmentBubble.boxSize(width: width, height: height)
    }

    // Task 3b — the OTHER participant's own name (host name for a guest,
    // guest name for an organizer), set once at openThread()/openChat(for:)
    // time since it depends on which side of the thread I'm on, not just
    // the event. Falls back to event.hostShort for the one caller that
    // doesn't know it yet (a 'new_message' notification tap).
    private var headerTitle: String { app.chatOtherName.isEmpty ? event.hostShort : app.chatOtherName }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Button("‹ " + (app.chatBack == .inbox ? app.T("Tin nhắn", "Messages") : app.chatBack == .notifications ? app.T("Thông báo", "Notifications") : event.orgName)) {
                    app.chatBackAction()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.back")
                Text(headerTitle).font(BanbeTheme.display(18))
                // Task 3b — event date + name subtitle directly under the title.
                Text("\(event.when) · \(event.name)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
            }
            Spacer()
            Button(app.T("Chi tiết", "Details")) { app.goEvent(event.key) }
                .font(.system(size: 11.5, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(app.palette.field, in: Capsule())
                .accessibilityIdentifier("chat.details")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if app.chatMessages.isEmpty {
                        bubble(text: event.greeting, mine: false, messageID: nil, senderLabel: headerTitle, createdAt: nil, attachmentPath: nil, attachmentType: nil)
                    }
                    ForEach(app.chatMessages) { message in
                        // Task 2 — unread divider: rendered once, right
                        // above the first message that was unread at the
                        // moment this thread was opened
                        // (app.chatUnreadDividerID, captured once by
                        // loadChatMessages(_:computeDivider:)). Naturally
                        // disappears on the next open since those rows are
                        // marked read immediately.
                        if message.id == app.chatUnreadDividerID {
                            unreadDivider
                        }
                        if message.kind == "system", let card = classifySystemMessage(message.body) {
                            systemCard(card, message: message)
                        } else {
                            bubble(
                                text: message.body, mine: message.senderId == app.userID,
                                messageID: message.id,
                                senderLabel: message.senderId == app.userID ? app.T("Bạn", "You") : headerTitle,
                                createdAt: message.createdAt,
                                attachmentPath: message.attachmentPath, attachmentType: message.attachmentType,
                                attachmentWidth: message.attachmentWidth, attachmentHeight: message.attachmentHeight,
                                replyToMessageId: message.replyToMessageId
                            )
                            .id(message.id)
                        }
                    }
                    // Stable bottom anchor, so a scroll-to-end works even when the
                    // last row is a system card (which carries no id of its own).
                    Color.clear.frame(height: 1).id("chat.bottom")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                // Clearance for the composer, the home indicator and the
                // bottom tab bar's collapsed strip. Without it the last
                // message — and, inside a dispute block, the newest message of
                // the dispute — can end up underneath them and look clipped.
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: app.chatMessages.count) {
                if let last = app.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            // The dispute panel has no scroll view of its own (see
            // DisputeChatPanel): this conversation's proxy is what carries its
            // scroll-to requests — the end of the history on open/own send, a
            // specific message on a dispute_message deep link.
            // The dispute block is tall. When it leaves this scroll view (the
            // goer deleted their copy, or the dispute concluded) the content
            // shrinks beneath an offset that was valid a moment ago, which left
            // an empty viewport until the chat was reopened. Re-anchor to the end.
            .onChange(of: app.conversationRefundDispute?.refundClaimId) { _, _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    proxy.scrollTo("chat.bottom", anchor: .bottom)
                }
            }
            .onChange(of: app.disputeChatScrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .bottom) }
                app.disputeChatScrollTarget = nil
            }
        }
    }

    private var unreadDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(app.palette.rule).frame(height: 1)
            Text("(\(app.T("Chưa đọc", "Unread")))")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(BanbeTheme.alert)
            Rectangle().fill(app.palette.rule).frame(height: 1)
        }
        .opacity(0.55)
        .padding(.vertical, 4)
        .accessibilityIdentifier("chat.unreadDivider")
    }

    // Task 3d — payment-status system messages as a distinct inline card
    // (reference: "Confirmed ... Show details"), not a plain text bubble.
    // messages.kind only has 'text'/'system' (schema-confirmed) — no
    // dedicated kind per lifecycle event — so this classifies by the exact
    // body prefix each RPC already writes today: confirm_payment()
    // (060:83), reject_pending_guest() (059:151), cancel_booking()
    // (022:167). Content-based, in the UI layer only, mirrors
    // src/screens/Chat.jsx's classifySystemMessage() exactly.
    private func classifySystemMessage(_ body: String) -> (status: String, label: String)? {
        if body.hasPrefix("Host marked payment received via") {
            return ("confirmed", app.T("Đã xác nhận thanh toán", "Payment confirmed"))
        }
        if body.hasPrefix("Người tổ chức không nhận yêu cầu đặt chỗ này") || body.hasPrefix("Booking cancelled.") {
            return ("declined", app.T("Đặt chỗ đã bị huỷ", "Booking cancelled"))
        }
        return nil
    }

    @ViewBuilder
    private func systemCard(_ card: (status: String, label: String), message: ChatMessage) -> some View {
        let attached = attachedDispute(for: card.status, message: message)
        // While the dispute is live the card IS the dispute block; once it
        // closes, the card collapses back to exactly the card it was, with
        // only a quiet "Dispute completed" line and a way back into the
        // transcript until the purge removes it.
        let expanded = attached != nil && (attached!.isActive || transcriptExpanded)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(card.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(card.status == "confirmed" ? app.palette.ink : BanbeTheme.alert)
                Spacer(minLength: 0)
                if attached?.isActive == true {
                    Text(app.T("Tranh chấp đang diễn ra", "Dispute in progress"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("chat.dispute.inProgress")
                } else if attached?.isCompleted == true {
                    Text(app.T("Tranh chấp đã hoàn tất", "Dispute completed"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
                        .accessibilityIdentifier("chat.dispute.completed")
                }
            }
            Text(message.body)
                .font(.system(size: 12.5))
                .foregroundStyle(app.palette.ink.opacity(0.75))
            Button(app.T("Xem chi tiết", "Show details")) { app.goEvent(event.key) }
                .font(.system(size: 11.5, weight: .semibold))
                .underline()
                .buttonStyle(.plain)

            if let attached {
                if expanded {
                    disputeBlock(attached)
                } else {
                    // Collapsed-but-concluded: the transcript is still here
                    // for the rest of the retention window, so the way in
                    // stays on the card rather than disappearing with it.
                    Button {
                        transcriptExpanded = true
                    } label: {
                        Text(app.T("Xem lại bản ghi tranh chấp ›", "Read the dispute transcript ›"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.dispute.openTranscript")
                }
            }

            // The OTHER dispute type — the host escalating a PAYMENT dispute
            // to banbe — hangs off the ONE "Payment confirmed" card selected
            // by disputeCardMessageIDs, and only while
            // conversationPaymentDisputeBookingID names a real, unresolved
            // payment dispute whose booking is still `payment_state =
            // 'disputed'`. BUG (2026-10-04, physical-iPhone repro): this used
            // to mount on EVERY confirmed card with no liveness check at all,
            // which is what put an empty spurious panel next to the real
            // refund dispute on a refund-only conversation. It keeps banbe's
            // admin-only resolution: nothing here closes it, exports nothing
            // on its behalf, and it collapses to the plain card once banbe has
            // ruled.
            if card.status == "confirmed",
               let paymentBookingID = app.conversationPaymentDisputeBookingID,
               disputeCardMessageIDs.payment == message.id {
                Divider().overlay(app.palette.rule).padding(.vertical, 2)
                DisputeChatPanel(bookingID: paymentBookingID)
                    .accessibilityIdentifier("chat.dispute.paymentPanel")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(attached?.isActive == true ? BanbeTheme.alert.opacity(0.55) : app.palette.rule, lineWidth: 1)
        )
        .foregroundStyle(app.palette.ink)
        .id(message.id)
        .accessibilityIdentifier("chat.systemCard")
    }

    /// Which dispute, if any, hangs off THIS system message — and, critically,
    /// whether it hangs off THIS ONE. Matched by exact ids and message
    /// metadata, never by event name or by "the only dispute on this screen".
    ///
    /// BUG (2026-10-04, physical-iPhone repro): this was `status == "declined"
    /// ? claim : nil`, so EVERY cancellation card in a conversation rendered
    /// its own copy of the same refund dispute, and each mounted copy ran its
    /// own poll against the shared global transcript state (disputeChatKey /
    /// disputeChatMessages / disputeChatDraft in AppState) — they fought over
    /// it and blanked each other. Two guards now make the attachment
    /// exclusive:
    ///
    /// 1. `disputeCardMessageIDs` names the ONE message each dispute belongs
    ///      to (DisputeCardAttachment.refundCardMessageID — the newest
    ///      cancellation at or before the claim's own `disputed_at`, else the
    ///      newest cancellation), and this returns the dispute only on that
    ///      exact message id.
    /// 2. The PAYMENT panel additionally requires `conversationPaymentDisputeBookingID`,
    ///      which AppState+Payments.loadConversationDispute() only sets for a
    ///      real, still-unresolved payment dispute whose booking is currently
    ///      `payment_state = 'disputed'` — so a refund-only conversation can
    ///      never mount one.
    private func attachedDispute(for status: String, message: ChatMessage) -> RefundDisputeThread? {
        // The refund half: a cancellation-driven refund dispute belongs to the
        // one "Booking cancelled" card loadConversationDispute() selected.
        if status == "declined",
           let claim = app.conversationRefundDispute, claim.found,
           disputeCardMessageIDs.refund == message.id {
            return claim
        }
        return nil
    }

    /// The ONE system message each dispute on this conversation belongs to.
    ///
    /// Historical `Booking cancelled.` / `Host marked payment received via …`
    /// system rows carry NO booking or claim id — messages has only
    /// (thread_id, sender_id, body, kind, …) and each cancellation RPC writes
    /// the same prose prefix — so there is no per-message booking identity to
    /// match on and matching "every declined card" is what mounted N copies of
    /// one dispute. The selection is therefore deterministic and documented:
    ///
    ///   refund  → the LAST cancellation card at or before the claim's own
    ///             `disputed_at`. A refund dispute is always raised AFTER the
    ///             cancellation that caused it, so the newest cancellation
    ///             preceding the dispute is the one it belongs to. Falls back
    ///             to the last cancellation card overall when the claim has no
    ///             usable timestamp.
    ///   payment → the FIRST "Payment confirmed" card. A payment dispute can
    ///             only exist after a payment was confirmed on that booking,
    ///             so the earliest confirmation is the one it hangs off.
    ///
    /// Both are pure functions of the loaded messages + the dispute's own
    /// timestamps, so the same conversation always renders the same single
    /// panel (no flicker between two cards across a poll), and a deep link's
    /// exact claim is still honoured — the claim id itself is never re-derived
    /// here, only which message hosts it.
    private var disputeCardMessageIDs: (refund: UUID?, payment: UUID?) {
        // ChatMessage carries strictly more than the rule needs, and the rule
        // itself (plus its rationale) lives in DisputeCardAttachment so it can
        // be unit-tested without a view — see Models/DisputeMessage.swift.
        let cards = app.chatMessages
            .filter { $0.kind == "system" }
            .map { DisputeCardAttachment.SystemMessage(id: $0.id, body: $0.body, createdAt: $0.createdAt) }
        return (
            DisputeCardAttachment.refundCardMessageID(in: cards, disputedAt: app.conversationRefundDispute?.disputedAt),
            DisputeCardAttachment.paymentCardMessageID(in: cards)
        )
    }

    /// The expanded dispute: status, amount, the temporary-chat notice, the
    /// full history, the composer, and the export/close actions. The panel
    /// itself owns the refresh loop and the transcript; this only decides it
    /// belongs on this card and that it renders INSIDE this conversation's
    /// scroll view (which is what makes every message reachable — see
    /// DisputeChatPanel's own note on the nested-scroll bug).
    @ViewBuilder
    private func disputeBlock(_ claim: RefundDisputeThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let amount = claim.amountVnd {
                    Text(formatVnd(amount))
                        .font(BanbeTheme.display(15))
                        .foregroundStyle(app.palette.ink)
                }
                Spacer(minLength: 0)
                if let status = claim.claimStatus {
                    Text(app.T("Trạng thái: \(status)", "Status: \(status)"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                        .accessibilityIdentifier("chat.dispute.claimStatus")
                }
            }
            Divider().overlay(app.palette.rule)
            DisputeChatPanel(
                refundClaimID: claim.refundClaimId,
                claim: claim
            )
            .accessibilityIdentifier("chat.dispute.panel")
        }
        .padding(.top, 6)
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // Task 3c — each bubble shows its own sender + timestamp, not just a
    // bare bubble. `createdAt` is nil only for the static greeting
    // placeholder (no real row to time-stamp).
    private func bubble(text: String, mine: Bool, messageID: UUID?, senderLabel: String, createdAt: Date?, attachmentPath: String?, attachmentType: String?, attachmentWidth: Int? = nil, attachmentHeight: Int? = nil, replyToMessageId: UUID? = nil) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if let createdAt {
                Text("\(senderLabel) · \(formattedTime(createdAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(app.palette.ink.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            // Task 3 (2026-09-22 follow-up) — a small reply-to-media
            // reference above the bubble, so a reply sent from the chat
            // photo viewer's own composer visibly points at the exact
            // image it answers. Resolved against the already-loaded
            // `app.chatMessages` — a reply's target is always in this same
            // thread, no second query needed.
            if let replyToMessageId, let replied = app.chatMessages.first(where: { $0.id == replyToMessageId }) {
                HStack(spacing: 6) {
                    if let path = replied.attachmentPath, let url = app.chatAttachmentUrls[path] {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Text(app.T("Trả lời ảnh", "Replying to a photo"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(app.palette.ink)
                }
                .opacity(0.7)
                .padding(.horizontal, 8)
                .overlay(Rectangle().fill(app.palette.rule).frame(width: 2), alignment: .leading)
                .accessibilityIdentifier("chat.replyReference")
            }
            HStack {
                if mine { Spacer(minLength: 40) }
                // Own messages only — messageID is nil for the static greeting
                // placeholder, and a system note is never `mine` (senderId nil
                // can't equal app.userID), so neither ever gets this.
                if mine, let messageID {
                    Button {
                        Task { await app.deleteMessage(messageID) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.message.delete")
                }
                // Task 4 — attachment rendering: an inline image for an
                // image/* attachment, a small document chip otherwise.
                // The signed URL comes from app.chatAttachmentUrls, the
                // same batched-signed-URL pattern `proofUrls` already uses
                // for the private payment-proof bucket.
                if let attachmentPath {
                    let url = app.chatAttachmentUrls[attachmentPath]
                    if attachmentType?.hasPrefix("image/") == true, let url {
                        // Task 1 (07-notifications.md) — an aspect-ratio-
                        // correct box computed from the stored intrinsic
                        // width/height (was a fixed 220x220 `.scaledToFit()`
                        // frame — the white-rail/letterbox bug: `.fit`
                        // inside a box whose ratio doesn't match the source
                        // image leaves empty space on two sides). The frame
                        // itself now has the image's OWN ratio, so `.fill`
                        // inside it never crops — it's simply filling a
                        // correctly-shaped box.
                        let box = Self.attachmentBoxSize(width: attachmentWidth, height: attachmentHeight)
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            .frame(width: box.width, height: box.height)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                            .accessibilityIdentifier("chat.attachment")
                            .onTapGesture {
                                app.openChatPhoto(messageId: messageID, attachmentPath: attachmentPath, url: url, width: attachmentWidth, height: attachmentHeight, senderLabel: senderLabel)
                            }
                    } else {
                        Link(destination: url ?? URL(string: "about:blank")!) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                Text(text)
                            }
                            .font(.system(size: 12.5))
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .accessibilityIdentifier("chat.attachment")
                    }
                } else {
                    Text(text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(mine ? app.palette.paper : app.palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(
                            mine ? app.palette.ink : app.palette.paper,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(mine ? .clear : app.palette.rule, lineWidth: 1)
                        )
                }
                if !mine { Spacer(minLength: 40) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(app.palette.rule)
            Group {
            if app.normalMessagingPaused {
                Text(app.T("Tin nhắn thông thường sẽ tiếp tục khi tranh chấp này được đóng.",
                           "Normal messaging will resume once this dispute is closed."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("chat.messagingPaused")
            } else {
            HStack(spacing: 8) {
                // Task 4 — "+" attach button + its two-option menu, now the
                // shared ChatAttachButton the temporary refund dispute
                // composer uses too. It owns the pickers and the re-encode;
                // this view still owns the upload and the send.
                ChatAttachButton(
                    isEnabled: app.chatThreadID != nil,
                    isSending: sendingAttachment
                ) { payload in
                    sendingAttachment = true
                    _ = await app.sendChatAttachment(
                        data: payload.data, contentType: payload.contentType,
                        fileExtension: payload.fileExtension,
                        width: payload.width, height: payload.height
                    )
                    sendingAttachment = false
                }

                TextField(
                    app.chatThreadID != nil
                        ? app.T("Viết cho \(event.hostShort)…", "Message \(event.hostShort)…")
                        : app.T("Đang mở cuộc trò chuyện…", "Opening conversation…"),
                    text: $app.chatDraft
                )
                .font(.system(size: 13.5))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.field, in: Capsule())
                .disabled(app.chatThreadID == nil)
                .focused($composerFocused)
                .onSubmit { Task { await app.chatSend() } }

                Button(app.T("Gửi", "Send")) { Task { await app.chatSend() } }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(app.palette.ink, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(app.chatThreadID == nil)
                    .opacity(app.chatThreadID == nil ? 0.5 : 1)
            }
            }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

/// Redesigned to read like Instagram/Facebook's own notification list
/// (07-notifications.md's 2026-09-18 follow-up): a left avatar per row
/// (derived per-kind — see avatarSource(for:maps:accountType:)), a bold
/// title + single-line truncated preview, and time-based sections with
/// unread always pinned to the top regardless of age. Same fonts/colors as
/// everywhere else in the app (BanbeTheme/app.palette) — no new design system.
private let notificationCollapseAt = 20

// TASK D — one semantic trailing icon per notification title, by kind
// category. Mirrors src/screens/Notifications.jsx's own KIND_CATEGORY/
// KindIcon exactly — SF Symbols here instead of inline SVG (this app's own
// existing per-platform icon convention: AccountView.swift's `row(icon:)`
// already uses SF Symbols, not RowIcon's web-only inline SVG set).
private let notificationKindCategory: [String: String] = [
    "refund_marked_sent": "refund", "refund_confirmed": "refund", "refund_disputed": "refund", "refund_overdue": "refund",
    // Migration 130 — the closure notification belongs to the same family as
    // the dispute it ends; without this it falls back to the generic bell
    // while its tap handler already routes into the dispute card.
    "refund_dispute_closed": "refund", "refund_dispute_autoclose_soon": "refund",
    "dispute_message": "dispute", "dispute_resolved": "dispute", "payment_disputed": "dispute",
    "payment_awaiting_verification": "payment", "payment_confirmed": "payment", "payment_document_uploaded": "payment",
    "payment_document_replaced": "payment", "payment_verification_nudge": "payment", "payment_needs_info": "payment",
    "hold_created": "payment", "hold_expired": "payment",
    "booking_requested": "booking", "booking_cancelled": "booking", "booking_declined": "booking",
    "checked_in": "booking", "checkin_undo": "booking", "checkin_undone": "booking", "undo_check_in": "booking",
    "reject_pending_guest": "booking", "receipt_requested": "booking",
    "event_share": "event", "referral_joined": "event",
    "new_message": "message",
    // iPhone fix pass (2026-09-27), Issue 1 — these fell to "system" (the
    // generic bell) before; mirrors web's own new 'team' KIND_CATEGORY
    // entry (Notifications.jsx) exactly.
    "organizer_invite": "team", "organizer_invite_response": "team", "event_credit_invite": "team",
]
private func notificationCategory(_ kind: String) -> String { notificationKindCategory[kind] ?? "system" }

// Color-as-wayfinding pass (2026-09-27) — the SAME meaning -> color map
// AccountView's own group cards use (ROW_ACCENT_COLORS), consolidated to
// the 4 groups that actually exist there — money-related kinds ->
// "payments" (sand), booking/event -> "activity" (rose), team -> "team"
// (moss), message/system -> neutral (ink). Mirrors web's own
// `CATEGORY_ACCENT` (Notifications.jsx) value-for-value.
private let notificationCategoryAccent: [String: Color] = [
    "refund": ROW_ACCENT_COLORS["payments"]!, "payment": ROW_ACCENT_COLORS["payments"]!, "dispute": ROW_ACCENT_COLORS["payments"]!,
    "booking": ROW_ACCENT_COLORS["activity"]!, "event": ROW_ACCENT_COLORS["activity"]!,
    "team": ROW_ACCENT_COLORS["team"]!,
    "message": ROW_ACCENT_COLORS["preferences"]!, "system": ROW_ACCENT_COLORS["preferences"]!,
]

private struct NotificationKindIcon: View {
    let category: String
    private var symbolName: String {
        switch category {
        case "refund": return "banknote"
        case "dispute": return "exclamationmark.triangle"
        case "payment": return "creditcard"
        case "booking": return "calendar.badge.checkmark"
        case "event": return "calendar"
        case "message": return "bubble.left"
        case "team": return "person.2"
        default: return "bell"
        }
    }
    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background((notificationCategoryAccent[category] ?? ROW_ACCENT_COLORS["preferences"]!).opacity(0.33), in: Circle())
            .accessibilityHidden(true)
    }
}

struct NotificationsView: View {
    @EnvironmentObject var app: AppState
    // Which sections have had their "Xem thêm" tapped — purely a
    // render-time slice of already-loaded data (loadNotifications() fetches
    // up to 50 at once), so a plain local Set is enough; nothing here needs
    // a new query.
    @State private var expandedSections: Set<String> = []
    // TASK 2 (2026-09-22 eighteenth follow-up) — real root cause of "cannot
    // reach selection mode": `app.notificationSelectionMode`/
    // `app.selectedNotificationIDs` were added to AppState in a prior pass
    // but never actually referenced anywhere in THIS view — the only place
    // that renders Notifications at all. Reading directly off AppState
    // (not view-local @State) since deleteNotifications() and any other
    // future caller need the same source of truth.
    private var selectionMode: Bool { app.notificationSelectionMode }
    // 2026-09-18 follow-up (BUG 3): a notification's SECTION is decided
    // once — the first time this screen sees it — and frozen from then on,
    // keyed by id. Reading it only flips its own readAt (handled live in
    // row(_:), for the bold/dim weight), it never moves the row to a
    // different section. Without this, section membership was recomputed
    // from live readAt on every body re-render — app.notifications is also
    // overwritten wholesale every 5s by the app-wide toast poll
    // (startNotificationPolling(), AppState+Data.swift), so a plain
    // computed property re-shuffled a notification the instant either
    // markNotificationRead() OR that unrelated poll tick re-rendered this
    // screen — which is what "reading moves it" actually was.
    @State private var sectionMembership: [UUID: String] = [:]
    // TASK 2 (2026-09-22 nineteenth follow-up) — search, matching
    // InboxView's own search icon+field exactly (see that view's `header`/
    // `iconButton`). Filters title/body client-side, same plain-substring
    // convention InboxView's own search already uses.
    @State private var searchOpen = false
    @State private var query = ""
    @FocusState private var searchFieldFocused: Bool

    // TASK 1 (2026-09-22 twentieth follow-up) — real root cause of the
    // search reveal feeling faster than Inbox's: this screen's search
    // toggle never used `withAnimation` at all (an instant, unsprung state
    // flip), while InboxView's identical control wraps the same toggle in
    // its own `sheetAnimation`. Reusing the EXACT same spring params here
    // rather than inventing a new speed, per this ticket's own instruction.
    private static let sheetAnimation = Animation.spring(response: 0.6, dampingFraction: 0.85)

    private struct NotificationSection: Identifiable {
        let id: String
        let title: String
        let items: [AppNotification]
        // 2026-09-19 follow-up: "week"/"older" get a finer per-calendar-day
        // header underneath this section's own title; "new"/"today" stay
        // flat exactly as before, per this ticket's own ask.
        var dayGrouped: Bool = false
    }

    private func exitSelectionMode() {
        app.notificationSelectionMode = false
        app.selectedNotificationIDs = []
    }

    // TASK 2 (2026-09-22 nineteenth follow-up) — same shape as InboxView's
    // own private `iconButton(_:label:action:)` (MessagingViews.swift) —
    // not reused directly since that one's `private` to InboxView, but
    // identical sizing/styling for visual parity.
    // TASK 2 (2026-09-22 twentieth follow-up) — `tint` added so the
    // selection-mode "Cancel" control can render in the shared destructive
    // `alert` color, matching web's Notifications.jsx.
    private func iconButton(_ systemImage: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 34, height: 34)
                    .background(app.palette.field, in: Circle())
                Text(label).font(.system(size: 9.5)).opacity(0.7)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? app.palette.ink)
    }

    private func classifyAtLoad(_ n: AppNotification, now: Date) -> String {
        guard n.readAt == nil else {
            switch notificationAgeBucket(n.createdAt, now: now) {
            case .today: return "today"
            case .week: return "week"
            case .older: return "older"
            }
        }
        return "new"
    }

    /// Assigns a section to any notification not already in
    /// `sectionMembership` — called on load and whenever `app.notifications`
    /// changes, but never touches an id that's already been assigned.
    private func syncSectionMembership() {
        let now = Date()
        for n in app.notifications where sectionMembership[n.id] == nil {
            sectionMembership[n.id] = classifyAtLoad(n, now: now)
        }
    }

    // Exactly one bucket per key, regardless of how many unread items are
    // interleaved with read ones in app.notifications — grouping by a
    // frozen, pre-computed membership id can never split "Mới" into two
    // blocks the way a live re-scan keyed on readAt (recomputed mid-list)
    // could.
    // TASK 2 (2026-09-22 nineteenth follow-up) — filters the SOURCE list
    // before grouping, not the rendered sections, so a matching
    // notification still lands in its own frozen section.
    private var searchFiltered: [AppNotification] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return app.notifications }
        return app.notifications.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    private var sections: [NotificationSection] {
        var grouped: [String: [AppNotification]] = ["new": [], "today": [], "week": [], "older": []]
        let now = Date()
        for n in searchFiltered {
            let key = sectionMembership[n.id] ?? classifyAtLoad(n, now: now)
            grouped[key, default: []].append(n)
        }
        return [
            NotificationSection(id: "new", title: app.T("Mới", "New"), items: grouped["new"] ?? []),
            NotificationSection(id: "today", title: app.T("Hôm nay", "Today"), items: grouped["today"] ?? []),
            NotificationSection(id: "week", title: app.T("7 ngày qua", "Last 7 days"), items: grouped["week"] ?? [], dayGrouped: true),
            NotificationSection(id: "older", title: app.T("Cũ hơn", "Older"), items: grouped["older"] ?? [], dayGrouped: true),
        ].filter { !$0.items.isEmpty }
    }

    // Pulled out of the scrollable body (2026-09-29 follow-up) so this row
    // is a fixed sibling ABOVE `ScreenScaffold`, matching Messages/InboxView
    // where the title + icon buttons never move during a pull-to-refresh —
    // only the sections below shift/reveal the indicator underneath.
    private var notificationsHeader: some View {
        HStack(alignment: .center) {
            // "banbe" wordmark parity fix (2026-09-29, follow-
            // up: placed BEFORE the title, inline in the same
            // row — not as its own row above it) — matches
            // Home's own header wordmark (HomeView.swift).
            // Hidden while the search field is showing (there's
            // no room, and the field itself already reads as
            // this screen's own content).
            if !searchOpen {
                BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
            }
            // TASK 2 (2026-09-22 nineteenth follow-up) — "Done"
            // removed entirely from normal mode (this screen is
            // reached from the dock's own Notifications tab,
            // same as InboxView — no separate "done" affordance
            // needed there either). Search input replaces the
            // title exactly mirroring InboxView's own
            // search-open state.
            if searchOpen {
                TextField(app.T("Tìm thông báo…", "Search notifications…"), text: $query)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(app.palette.field, in: Capsule())
                    .foregroundStyle(app.palette.ink)
                    .focused($searchFieldFocused)
                    // TASK 1 (2026-09-22 twentieth follow-up) —
                    // same transition InboxView's own search
                    // field uses, not a bespoke one.
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if selectionMode {
                Text(app.T("Đang chọn", "Selecting")).font(BanbeTheme.display(27))
            } else {
                Text(app.T("Thông báo", "Notifications")).font(BanbeTheme.display(27))
            }
            Spacer()
            // TASK 2 (2026-09-22 twentieth follow-up) — the two
            // right-side slots persist across selection mode
            // (never removed/reinserted at a different spot in
            // the header) and their CONTENT crossfades via
            // `.id` + `.transition(.opacity)` under the shared
            // spring, so Search/Select morph into Select
            // all/Cancel in place instead of jumping the layout.
            HStack(spacing: 14) {
                if selectionMode {
                    iconButton("checklist", label: app.T("Chọn tất cả", "Select all")) {
                        app.selectedNotificationIDs = Set(app.notifications.map(\.id))
                    }
                    .id("select-all")
                    .accessibilityIdentifier("notifications.selectAll")
                    .transition(.opacity)
                } else {
                    iconButton(searchOpen ? "xmark" : "magnifyingglass", label: searchOpen ? app.T("Đóng", "Close") : app.T("Tìm", "Search")) {
                        if searchOpen { query = "" }
                        withAnimation(Self.sheetAnimation) { searchOpen.toggle() }
                        searchFieldFocused = searchOpen
                    }
                    .id("search")
                    .accessibilityIdentifier("notifications.searchToggle")
                    .transition(.opacity)
                }
                if selectionMode {
                    iconButton("xmark", label: app.T("Huỷ", "Cancel"), tint: BanbeTheme.alert) {
                        withAnimation(Self.sheetAnimation) { exitSelectionMode() }
                    }
                    .id("cancel")
                    .accessibilityIdentifier("notifications.selection.cancel")
                    .transition(.opacity)
                } else if !app.notifications.isEmpty {
                    iconButton("checkmark.circle", label: app.T("Chọn", "Select")) {
                        withAnimation(Self.sheetAnimation) { app.notificationSelectionMode = true }
                    }
                    .id("select")
                    .accessibilityIdentifier("notifications.selectMode")
                    .transition(.opacity)
                }
            }
            .animation(Self.sheetAnimation, value: selectionMode)
        }
        .padding(.bottom, selectionMode ? 8 : 14)
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    var body: some View {
        // Opaque-header fix (2026-09-29 follow-up, real-device report:
        // overlapping headers during a swipe-back transition) — see
        // HomeView's own identical fix for the full explanation:
        // `notificationsHeader` lost the opaque `app.palette.paper`
        // background it used to inherit for free from being inside
        // `ScreenScaffold`.
        ZStack {
        app.palette.paper.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
            notificationsHeader
            ZStack {
            ScreenScaffold(tracksBottomBarScroll: true, refreshIndicatorTopPadding: 16, onRefresh: { await app.loadNotifications() }) {
                VStack(alignment: .leading, spacing: 0) {
                    if selectionMode, !app.selectedNotificationIDs.isEmpty {
                        HStack {
                            Spacer()
                            Button(app.T("Xoá (\(app.selectedNotificationIDs.count))", "Delete (\(app.selectedNotificationIDs.count))")) {
                                Task {
                                    let ids = Array(app.selectedNotificationIDs)
                                    exitSelectionMode()
                                    await app.deleteNotifications(ids)
                                }
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(BanbeTheme.alert)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("notifications.deleteSelected")
                        }
                        .padding(.bottom, 12)
                    }

                    let allSections = sections
                    if allSections.isEmpty {
                        Text(app.T("Chưa có thông báo nào.", "No notifications yet."))
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    } else {
                        ForEach(allSections) { sec in
                            section(sec)
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .task {
                await app.loadNotifications()
                syncSectionMembership()
            }
            .onChange(of: app.notifications) { _, _ in syncSectionMembership() }
            }
        }
        }
    }

    private func section(_ sec: NotificationSection) -> some View {
        let expanded = expandedSections.contains(sec.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(sec.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(app.palette.ink.opacity(0.6))
            if !sec.dayGrouped {
                let visible = expanded ? sec.items : Array(sec.items.prefix(notificationCollapseAt))
                ForEach(visible) { item in
                    // Live readAt, not the (frozen) section — marking a
                    // notification read only changes its weight/dimming in
                    // place, per BUG 3, never which section it's in.
                    row(item, unread: item.readAt == nil)
                    Divider().overlay(app.palette.rule)
                }
                moreButton(hiddenCount: sec.items.count - visible.count, sectionID: sec.id)
            } else {
                // "7 ngày qua"/"Cũ hơn": one header per calendar day
                // underneath this section's own outer title, collapsing
                // whole days at a time (collapseDayGroups() never cuts a
                // single day's items in half) instead of a flat
                // notificationCollapseAt slice across the range.
                let dayGroups = groupNotificationsByDay(sec.items, lang: app.lang)
                let (visibleDays, hiddenDays): ([NotificationDayGroup], [NotificationDayGroup]) = expanded
                    ? (dayGroups, [])
                    : collapseDayGroups(dayGroups, limit: notificationCollapseAt)
                ForEach(visibleDays) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.5))
                            .accessibilityIdentifier("notification.dayHeader")
                        ForEach(day.items) { item in
                            row(item, unread: item.readAt == nil)
                            Divider().overlay(app.palette.rule)
                        }
                    }
                    .padding(.bottom, 8)
                }
                moreButton(hiddenCount: hiddenDays.reduce(0) { $0 + $1.items.count }, sectionID: sec.id)
            }
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func moreButton(hiddenCount: Int, sectionID: String) -> some View {
        if hiddenCount > 0 {
            Button(app.T("Xem thêm (\(hiddenCount))", "View more (\(hiddenCount))")) {
                expandedSections.insert(sectionID)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(app.palette.ink.opacity(0.65))
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .accessibilityIdentifier("notifications.more.\(sectionID)")
        }
    }

    private func toggleSelected(_ id: UUID) {
        if app.selectedNotificationIDs.contains(id) { app.selectedNotificationIDs.remove(id) }
        else { app.selectedNotificationIDs.insert(id) }
    }

    private func row(_ item: AppNotification, unread: Bool) -> some View {
        // TASK 2 (2026-09-22 eighteenth follow-up) — in selection mode a tap
        // toggles the checkbox instead of navigating (requirement 3: "does
        // not open it"), and the "•••" menu is hidden entirely (requirement
        // 5: selection must not depend on the three-dot menu).
        let selected = app.selectedNotificationIDs.contains(item.id)
        return HStack(alignment: .top, spacing: 10) {
            // Accidental-tap-during-navigation fix (2026-09-29) — a
            // deliberate tap that opened Notifications (a dock tap, a
            // completed/aborted tab-swipe) could leave the finger
            // resting on/near this first row the instant the screen
            // arrives; a plain `Button`'s own touch tracking only checks
            // "did release land inside my bounds," not "how far did the
            // touch travel to get here" — see `SwipeSafeButton`'s own doc
            // comment (Components.swift) for the full root-cause writeup,
            // confirmed there first on Home's identical rows.
            SwipeSafeButton {
                if selectionMode { toggleSelected(item.id) } else { app.openNotification(item) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    if selectionMode {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? BanbeTheme.alert : app.palette.rule)
                            .accessibilityIdentifier("notification.row.checkbox")
                    }
                    avatar(for: item)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            // BUG 3: bold only while unread — reading a
                            // notification unbolds it in place (fontWeight
                            // only), it never moves sections.
                            Text(item.title)
                                .font(BanbeTheme.display(15))
                                .fontWeight(unread ? .bold : .regular)
                                .lineLimit(1)
                            NotificationKindIcon(category: notificationCategory(item.kind))
                            Spacer(minLength: 12)
                            Text(app.trStatus(EventLabels.ago(hoursAgo(item.createdAt))))
                                .font(.system(size: 11))
                        }
                        // Instagram's own "bold actor/action + secondary
                        // preview" shape — one truncated line, not the old
                        // full-body wrap.
                        Text(item.body)
                            .font(.system(size: 13))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification.row")

            // Notifications options display fix pass (2026-09-28) — was a
            // text "•••" `Button` opening a custom `BottomSheet` (needing
            // its own `app.modalActionSheetPresented` wiring just to hide
            // the always-on-top dock overlay while it was up). Now the
            // same tap-only "…" `Menu` pattern `InboxRow` uses for
            // Star/Archive (MessagingViews.swift, `InboxRow`'s own doc
            // comment) — a native `Menu` needs no such wiring (it
            // presents above everything on its own), and this keeps the
            // two dock-tab row-actions controls visually/behaviorally
            // identical. Hidden in selection mode — normal-mode-only per
            // this ticket's own requirement 1.
            if !selectionMode {
                Menu {
                    Button {
                        Task {
                            if item.readAt != nil { await app.markNotificationUnread(item) } else { await app.markNotificationRead(item) }
                        }
                    } label: {
                        Label(item.readAt != nil ? app.T("Đánh dấu chưa đọc", "Mark as unread") : app.T("Đánh dấu đã đọc", "Mark as read"), systemImage: item.readAt != nil ? "envelope.badge" : "envelope.open")
                    }
                    .accessibilityIdentifier("notification.menu.toggleRead")
                    Button {
                        Task { await app.muteNotificationKind(item.kind) }
                    } label: {
                        Label(app.T("Tắt loại thông báo này", "Turn off this kind of notification"), systemImage: "bell.slash")
                    }
                    .accessibilityIdentifier("notification.menu.mute")
                    Button(role: .destructive) {
                        Task { await app.deleteNotification(item) }
                    } label: {
                        Label(app.T("Xoá thông báo này", "Delete this notification"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("notification.menu.delete")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.4))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("notification-menu")
            }
        }
        // TASK D — unread: a clearly darker/tinted background + bold title
        // (unchanged above); read: normal (clear) background. Replaces the
        // old whole-row `.opacity(unread ? 1 : 0.6)` fade, which dimmed
        // everything in a read row rather than distinguishing the two
        // states via background.
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(unread ? app.palette.ink.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func avatar(for item: AppNotification) -> some View {
        switch avatarSource(for: item, maps: app.notificationAvatarMaps, accountType: app.accountType) {
        case .image(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        case .catalogPhoto(let path):
            CatalogPhoto(path: path, height: 40, width: 40, cornerRadius: 20)
        case .teamFallback:
            teamAvatarFallback
        case .fallback:
            avatarFallback
        }
    }

    // A plain colored circle with the app's own bell mark — never a broken
    // image. Used whenever avatarSource(for:maps:accountType:) can't
    // resolve an event photo or a guest avatar (neither exists, or the
    // notification kind has no specific actor at all, e.g. referral_joined).
    private var avatarFallback: some View {
        Circle()
            .fill(app.palette.ink.opacity(0.08))
            .frame(width: 40, height: 40)
            .overlay(Text("🔔").font(.system(size: 16)))
    }

    // iPhone fix pass (2026-09-27), Issue 1 — same circle, a people glyph
    // instead of the bell, for organizer_invite/organizer_invite_response/
    // event_credit_invite whenever no real organizer avatar/event photo
    // resolved either.
    private var teamAvatarFallback: some View {
        Circle()
            .fill(app.palette.ink.opacity(0.08))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(app.palette.ink.opacity(0.55)))
    }

    private func hoursAgo(_ date: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(date) / 3600))
    }
}

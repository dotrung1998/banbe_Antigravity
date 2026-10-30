import Foundation

// Guest browsing (note 48, principles 3 + 4 of the UX psychology pass):
// signed-out people can look at real events first; the sign-in ask comes
// at the moment it is needed, says why, and resumes what they were doing.

enum GuestPromptContext: String {
    case save, follow, reserve, message, like
    // Simple Shell (note 66): the Home "Hosting" segment and the dock "+" rows.
    case host, schedule, invite
}

/// Work to finish once the guest has signed in from a prompt.
enum AuthResume: Equatable {
    case reserve(eventKey: String)
    case chat(eventKey: String, back: Screen)
}

struct GuestPrompt: Identifiable, Equatable {
    let id = UUID()
    let context: GuestPromptContext
    let returnTo: Screen
    let backTo: Screen
    var resume: AuthResume? = nil
}

extension AppState {
    /// Ask a guest to sign in for `context`, without leaving the screen yet.
    func promptSignIn(_ context: GuestPromptContext, returnTo: Screen? = nil, backTo: Screen? = nil,
                      resume: AuthResume? = nil) {
        guestPrompt = GuestPrompt(context: context, returnTo: returnTo ?? screen, backTo: backTo ?? screen,
                                  resume: resume)
        Analytics.track(.guestSignInPromptShown(context: context.rawValue))
    }

    /// The sheet's Continue / Log in: go to Login with the right intent.
    func continueFromGuestPrompt(_ intent: AuthEntryIntent) {
        guard let prompt = guestPrompt else { return }
        guestPrompt = nil
        Analytics.track(.guestSignInPromptAccepted(context: prompt.context.rawValue))
        pendingAuthResume = prompt.resume
        authIntent = intent
        requireAuth(returnTo: prompt.returnTo, backTo: prompt.backTo)
    }

    /// Called once a sign-in has fully applied (RootView).
    func runPendingAuthResume() {
        guard isSignedIn, let resume = pendingAuthResume else { return }
        pendingAuthResume = nil
        switch resume {
        case .reserve(let key):
            eventKey = key
            goReserve()
        case .chat(let key, let back):
            Task { await openChat(for: key, back: back) }
        }
    }

    /// Welcome → "Explore events": browse Home signed out.
    func browseAsGuest() {
        Analytics.track(.guestBrowseStarted)
        authNavForward = true
        screen = .home
    }

    static func guestPromptCopy(_ context: GuestPromptContext, T: (String, String) -> String) -> (title: String, body: String) {
        switch context {
        case .save:
            return (T("Lưu sự kiện này", "Save this event"),
                    T("Đăng nhập để lưu sự kiện và xem lại trên mọi thiết bị.", "Log in to keep your saved events on every device."))
        case .follow:
            return (T("Theo dõi host này", "Follow this host"),
                    T("Đăng nhập để nhận sự kiện mới của host bạn theo dõi.", "Log in to hear about new events from hosts you follow."))
        case .reserve:
            return (T("Giữ chỗ của bạn", "Hold your seat"),
                    T("Đăng nhập để giữ chỗ. Bạn sẽ quay lại đúng sự kiện này.", "Log in to hold your seat. You'll come right back to this event."))
        case .message:
            return (T("Nhắn tin cho host", "Message the host"),
                    T("Đăng nhập để nhắn tin. Bạn sẽ quay lại đúng cuộc trò chuyện này.", "Log in to send a message. You'll come right back to this chat."))
        case .like:
            return (T("Thích ảnh này", "Like this photo"),
                    T("Đăng nhập để thích ảnh và ủng hộ host.", "Log in to like photos and support the host."))
        case .host:
            return (T("Tổ chức sự kiện", "Host an event"),
                    T("Đăng nhập để tổ chức sự kiện của riêng bạn. Miễn phí khi banbe còn mới.", "Log in to host your own events. Free while banbe is new."))
        case .schedule:
            return (T("Thêm vào lịch của bạn", "Add to your schedule"),
                    T("Đăng nhập để lưu các buổi bạn muốn đi vào lịch của bạn.", "Log in to keep the plans you want to go to in your schedule."))
        case .invite:
            return (T("Mời bạn bè", "Invite friends"),
                    T("Đăng nhập để lấy đường dẫn mời của riêng bạn.", "Log in to get your own invite link."))
        }
    }
}

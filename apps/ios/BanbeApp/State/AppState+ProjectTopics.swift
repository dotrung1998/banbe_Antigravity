import Foundation

/// Event Project Hub phase 4 (note 76): Topics. Structured posts only (Proposal, Question, Update, Decision): votes and
/// "Seen" are counters, replies are capped at 10 × 140 characters, a settled post locks. Every action is one RPC from
/// migration 210 followed by a version-checked refresh. In a DEBUG UI fixture the snapshot changes in memory instead.
extension AppState {
    /// One post with its replies, voters and who has seen it (the thread sheet).
    func loadProjectPost(_ postID: String) async -> ProjectPostDetail? {
        #if DEBUG
        if UITestFixture.isActive {
            guard let post = projectSnapshot?.posts?.first(where: { $0.id == postID }) else { return nil }
            return ProjectPostDetail(success: true, error: nil, post: post, replies: UITestFixture.projectReplies[postID] ?? [],
                                     voters: [], seenBy: post.seenByMe ? [userID?.uuidString.lowercased() ?? ""] : [])
        }
        #endif
        struct Params: Encodable {
            let pPostId: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id" }
        }
        do {
            let result: ProjectPostDetail = try await SupabaseService.client.rpc("get_event_project_post", params: Params(pPostId: postID))
                .execute().value
            if !result.success { projectNotice = projectErrorText(result.error) }
            return result.success ? result : nil
        } catch {
            print("loadProjectPost failed:", error)
            projectNotice = projectErrorText(nil)
            return nil
        }
    }

    /// The next 20 older posts, kept below the snapshot's own 20 (refreshes keep them, see `mergeOlderPosts`).
    func loadOlderProjectPosts() async {
        #if DEBUG
        if UITestFixture.isActive { projectPostsExhausted = true; return }
        #endif
        guard let oldest = projectSnapshot?.posts?.last?.createdAt else { projectPostsExhausted = true; return }
        struct Params: Encodable {
            let pEventId: String; let pBefore: String; let pLimit: Int
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pBefore = "p_before", pLimit = "p_limit" }
        }
        do {
            let page: ProjectPostsPage = try await SupabaseService.client
                .rpc("get_event_project_posts", params: Params(pEventId: projectEventID, pBefore: oldest, pLimit: 20)).execute().value
            let older = page.posts ?? []
            let known = Set((projectSnapshot?.posts ?? []).map(\.id))
            projectSnapshot?.posts = (projectSnapshot?.posts ?? []) + older.filter { !known.contains($0.id) }
            projectPostsExhausted = older.count < 20
        } catch {
            print("loadOlderProjectPosts failed:", error)
            projectNotice = projectErrorText(nil)
        }
    }

    /// A fresh snapshot carries the newest 20 posts; older pages the user already opened stay below them.
    func mergeOlderPosts(into next: inout ProjectSnapshot) {
        guard let old = projectSnapshot?.posts, let fresh = next.posts, fresh.count >= 20,
              let oldest = fresh.last.flatMap({ ProjectDates.parse($0.createdAt) }) else { return }
        let ids = Set(fresh.map(\.id))
        next.posts = fresh + old.filter { p in
            !ids.contains(p.id) && (ProjectDates.parse(p.createdAt).map { $0 < oldest } ?? false)
        }
    }

    @discardableResult
    func createProjectPost(type: String, laneID: String, title: String, body: String, options: [String]?, addresseeID: String?,
                           deadline: String?) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            let me = userID?.uuidString.lowercased()
            let post = ProjectPost(id: UUID().uuidString.lowercased(), laneId: laneID, type: type, title: title, body: body, authorId: me,
                                   addresseeId: type == "question" ? addresseeID : nil, options: type == "proposal" ? options : nil,
                                   deadline: type == "proposal" ? deadline : nil, state: type == "decision" ? "locked" : "open",
                                   createdAt: ISO8601DateFormatter().string(from: projectNow), editedAt: nil,
                                   votes: type == "proposal" ? Array(repeating: 0, count: options?.count ?? 0) : nil, myVote: nil,
                                   repliesCount: 0, seenCount: type == "update" || type == "decision" ? 1 : 0,
                                   seenByMe: type == "update" || type == "decision", quiet: true)
            projectSnapshot?.posts = [post] + (projectSnapshot?.posts ?? [])
            return true
        }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pType: String; let pLaneId: String; let pTitle: String; let pBody: String
            let pOptions: [String]?; let pAddresseeId: String?; let pDeadline: String?
            enum CodingKeys: String, CodingKey {
                case pEventId = "p_event_id", pType = "p_type", pLaneId = "p_lane_id", pTitle = "p_title", pBody = "p_body"
                case pOptions = "p_options", pAddresseeId = "p_addressee_id", pDeadline = "p_deadline"
            }
        }
        return await projectWrite("project_create_post", Params(pEventId: projectEventID, pType: type, pLaneId: laneID, pTitle: title,
                                                                pBody: body, pOptions: options, pAddresseeId: addresseeID,
                                                                pDeadline: deadline), post: true)
    }

    @discardableResult
    func editProjectPost(_ postID: String, title: String, body: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            fixtureEditPost(postID) { $0.title = title; $0.body = body; $0.editedAt = ISO8601DateFormatter().string(from: projectNow) }
            return true
        }
        #endif
        struct Params: Encodable {
            let pPostId: String; let pTitle: String; let pBody: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id", pTitle = "p_title", pBody = "p_body" }
        }
        return await projectWrite("project_edit_post", Params(pPostId: postID, pTitle: title, pBody: body), post: true)
    }

    /// One vote each; the same option again takes the vote back.
    @discardableResult
    func voteProjectPost(_ postID: String, option: Int) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            fixtureEditPost(postID) { p in
                var votes = p.votes ?? []
                guard votes.indices.contains(option) else { return }
                if let had = p.myVote, votes.indices.contains(had) { votes[had] -= 1 }
                if p.myVote == option { p.myVote = nil } else { votes[option] += 1; p.myVote = option }
                p.votes = votes
                p.quiet = false
            }
            return true
        }
        #endif
        struct Params: Encodable {
            let pPostId: String; let pOption: Int
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id", pOption = "p_option" }
        }
        return await projectWrite("project_vote", Params(pPostId: postID, pOption: option), post: true)
    }

    @discardableResult
    func markProjectPostSeen(_ postID: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            fixtureEditPost(postID) { p in
                guard !p.seenByMe else { return }
                p.seenByMe = true; p.seenCount += 1; p.quiet = false
            }
            return true
        }
        #endif
        struct Params: Encodable {
            let pPostId: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id" }
        }
        return await projectWrite("project_mark_seen", Params(pPostId: postID), post: true)
    }

    @discardableResult
    func replyProjectPost(_ postID: String, body: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            let reply = ProjectReply(id: UUID().uuidString.lowercased(), authorId: userID?.uuidString.lowercased(), body: body,
                                     createdAt: ISO8601DateFormatter().string(from: projectNow))
            UITestFixture.projectReplies[postID, default: []].append(reply)
            fixtureEditPost(postID) { $0.repliesCount += 1; $0.quiet = false }
            return true
        }
        #endif
        struct Params: Encodable {
            let pPostId: String; let pBody: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id", pBody = "p_body" }
        }
        return await projectWrite("project_reply", Params(pPostId: postID, pBody: body), post: true)
    }

    /// Close a question (or a proposal without deciding): the post locks.
    @discardableResult
    func resolveProjectPost(_ postID: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive { fixtureEditPost(postID) { $0.state = "resolved" }; return true }
        #endif
        struct Params: Encodable {
            let pPostId: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id" }
        }
        return await projectWrite("project_resolve_post", Params(pPostId: postID), post: true)
    }

    /// Settle a proposal on the leading option: it resolves and a locked Decision joins the decision log.
    @discardableResult
    func decideProjectProposal(_ postID: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            guard let p = projectSnapshot?.posts?.first(where: { $0.id == postID }), let options = p.options, !options.isEmpty else { return false }
            let votes = p.votes ?? []
            let best = options.indices.max { (votes.indices.contains($0) ? votes[$0] : 0, -$0) < (votes.indices.contains($1) ? votes[$1] : 0, -$1) } ?? 0
            fixtureEditPost(postID) { $0.state = "resolved" }
            return await createProjectPost(type: "decision", laneID: p.laneId, title: options[best], body: p.title, options: nil,
                                           addresseeID: nil, deadline: nil)
        }
        #endif
        struct Params: Encodable {
            let pPostId: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id" }
        }
        return await projectWrite("project_decide_proposal", Params(pPostId: postID), post: true)
    }

    @discardableResult
    func deleteProjectPost(_ postID: String, reason: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive { projectSnapshot?.posts?.removeAll { $0.id == postID }; return true }
        #endif
        struct Params: Encodable {
            let pPostId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pPostId = "p_post_id", pReason = "p_reason" }
        }
        return await projectWrite("project_delete_post", Params(pPostId: postID, pReason: reason), post: true)
    }

    #if DEBUG
    private func fixtureEditPost(_ postID: String, _ change: (inout ProjectPost) -> Void) {
        guard let i = projectSnapshot?.posts?.firstIndex(where: { $0.id == postID }) else { return }
        change(&projectSnapshot!.posts![i])
    }
    #endif

    // MARK: words

    func projectPostTypeName(_ type: String) -> String {
        switch type {
        case "proposal": return T("Đề xuất", "Proposal")
        case "question": return T("Câu hỏi", "Question")
        case "update": return T("Cập nhật", "Update")
        default: return T("Quyết định", "Decision")
        }
    }

    func projectPostTypeHint(_ type: String) -> String {
        switch type {
        case "proposal": return T("Nhiều lựa chọn, cả đội bỏ phiếu đến hạn chót.", "Several options. The team votes by a deadline.")
        case "question": return T("Hỏi đúng một người. Có người trả lời thì đóng.", "Ask one named person. Close it once answered.")
        case "update": return T("Báo tin một chiều. Mọi người chỉ bấm “Đã xem”.", "One-way news. People just tap “Seen”.")
        default: return T("Chốt một việc và khoá lại, lưu vào nhật ký.", "Settle something, lock it and log it.")
        }
    }

    func projectPostIcon(_ type: String) -> String {
        switch type {
        case "proposal": return "chart.bar"
        case "question": return "questionmark.bubble"
        case "update": return "info.circle"
        default: return "flag"
        }
    }

    /// Everyone who can answer, vote or see a post: the Hosts and the active members.
    var projectHeadcount: Int { (projectSnapshot?.hosts?.count ?? 0) + (projectSnapshot?.members?.count ?? 0) }
}

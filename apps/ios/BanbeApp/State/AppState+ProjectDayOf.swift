import Foundation

/// Event Project Hub phase 5 (note 76): Day-of. The run-of-show (writes: Host and Managers; ticks: everyone), the
/// event-day poll and the trash. Times are instants on the server and shown in the EVENT's zone; a tick's time is the
/// server's, never the phone's.
extension AppState {
    // MARK: poll

    /// Live sync is on only while all three hold: the Day-of tab is showing, the app is in front, and today is the
    /// event day in the event's zone. Otherwise the project syncs on open and on pull to refresh.
    func projectLiveSyncOn(scenePhaseActive: Bool) -> Bool {
        guard scenePhaseActive, screen == .eventProject, projectTab == "dayof", let event = projectSnapshot?.event else { return false }
        return ProjectPresentation.daysToGo(event, now: projectNow) == 0
    }

    /// One poll: run-of-show only, and a tiny {unchanged} answer when nothing moved.
    func pollProjectRos() async {
        if projectOffline { return }
        guard !projectEventID.isEmpty else { return }
        struct Params: Encodable {
            let pEventId: String; let pSinceVersion: Int?
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pSinceVersion = "p_since_version" }
        }
        let eventID = projectEventID
        do {
            let result: ProjectRosResult = try await SupabaseService.client
                .rpc("get_event_project_ros", params: Params(pEventId: eventID, pSinceVersion: projectRosVersion ?? projectSnapshot?.version))
                .execute().value
            guard eventID == projectEventID, result.success else { return }
            projectRosVersion = result.version
            if result.unchanged != true, let ros = result.ros { projectSnapshot?.ros = ros }
        } catch {
            print("pollProjectRos failed:", error)
        }
    }

    // MARK: run-of-show writes

    /// Create (itemID nil) or edit an item. `startsAt` / `endsAt` are instants (the sheet picks them in the event's zone).
    @discardableResult
    func saveProjectRosItem(itemID: String?, title: String, ownerID: String?, startsAt: Date, endsAt: Date) async -> Bool {
        let iso = ISO8601DateFormatter()
        if projectOffline {
            if let itemID, let i = projectSnapshot?.ros?.firstIndex(where: { $0.id == itemID }) {
                projectSnapshot?.ros?[i].title = title
                projectSnapshot?.ros?[i].ownerId = ownerID
                projectSnapshot?.ros?[i].startsAt = iso.string(from: startsAt)
                projectSnapshot?.ros?[i].endsAt = iso.string(from: endsAt)
            } else {
                let item = ProjectRosItem(id: UUID().uuidString.lowercased(), title: title, ownerId: ownerID,
                                          startsAt: iso.string(from: startsAt), endsAt: iso.string(from: endsAt), doneAt: nil)
                projectSnapshot?.ros = ((projectSnapshot?.ros ?? []) + [item])
                    .sorted { (ProjectDates.parse($0.startsAt) ?? .distantPast) < (ProjectDates.parse($1.startsAt) ?? .distantPast) }
            }
            return true
        }
        struct Params: Encodable {
            let pEventId: String; let pItemId: String?; let pTitle: String; let pOwnerId: String?; let pStartsAt: String; let pEndsAt: String
            enum CodingKeys: String, CodingKey {
                case pEventId = "p_event_id", pItemId = "p_item_id", pTitle = "p_title", pOwnerId = "p_owner_id"
                case pStartsAt = "p_starts_at", pEndsAt = "p_ends_at"
            }
            func encode(to encoder: Encoder) throws {
                // Always send every key: a nil owner must clear it, not be skipped.
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(pEventId, forKey: .pEventId); try c.encode(pItemId, forKey: .pItemId); try c.encode(pTitle, forKey: .pTitle)
                try c.encode(pOwnerId, forKey: .pOwnerId); try c.encode(pStartsAt, forKey: .pStartsAt); try c.encode(pEndsAt, forKey: .pEndsAt)
            }
        }
        return await projectWrite("project_upsert_ros_item", Params(pEventId: projectEventID, pItemId: itemID, pTitle: title, pOwnerId: ownerID,
                                                                    pStartsAt: iso.string(from: startsAt), pEndsAt: iso.string(from: endsAt)),
                                  ros: true)
    }

    /// Tick or untick. Everyone in the project may; the server stamps the time.
    @discardableResult
    func tickProjectRosItem(_ itemID: String, done: Bool) async -> Bool {
        if projectOffline {
            guard let i = projectSnapshot?.ros?.firstIndex(where: { $0.id == itemID }) else { return false }
            projectSnapshot?.ros?[i].doneAt = done ? ISO8601DateFormatter().string(from: projectNow) : nil
            return true
        }
        struct Params: Encodable {
            let pItemId: String; let pDone: Bool
            enum CodingKeys: String, CodingKey { case pItemId = "p_item_id", pDone = "p_done" }
        }
        return await projectWrite("project_tick_ros_item", Params(pItemId: itemID, pDone: done))
    }

    @discardableResult
    func deleteProjectRosItem(_ itemID: String, reason: String) async -> Bool {
        if projectOffline {
            if let item = projectSnapshot?.ros?.first(where: { $0.id == itemID }) {
                ProjectDemo.trash.insert(ProjectTrashItem(kind: "ros", itemId: itemID, title: item.title, by: userID?.uuidString.lowercased(),
                                                                   reason: reason, at: ISO8601DateFormatter().string(from: projectNow),
                                                                   startsAt: item.startsAt), at: 0)
            }
            projectSnapshot?.ros?.removeAll { $0.id == itemID }
            return true
        }
        struct Params: Encodable {
            let pItemId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pItemId = "p_item_id", pReason = "p_reason" }
        }
        return await projectWrite("project_delete_ros_item", Params(pItemId: itemID, pReason: reason))
    }

    // MARK: trash (Host and Managers; purging is the Host's)

    func loadProjectTrash() async -> [ProjectTrashItem] {
        if projectOffline { return ProjectDemo.trash }
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        do {
            let result: ProjectTrashResult = try await SupabaseService.client
                .rpc("get_event_project_trash", params: Params(pEventId: projectEventID)).execute().value
            if !result.success { projectNotice = projectErrorText(result.error) }
            return result.items ?? []
        } catch {
            print("loadProjectTrash failed:", error)
            projectNotice = projectErrorText(nil)
            return []
        }
    }

    @discardableResult
    func restoreProjectItem(_ item: ProjectTrashItem) async -> Bool {
        if projectOffline {
            ProjectDemo.trash.removeAll { $0.id == item.id }
            if item.kind == "ros", let start = item.startsAt, let s = ProjectDates.parse(start) {
                let back = ProjectRosItem(id: item.itemId, title: item.title, ownerId: nil, startsAt: start,
                                          endsAt: ISO8601DateFormatter().string(from: s.addingTimeInterval(1800)), doneAt: nil)
                projectSnapshot?.ros = ((projectSnapshot?.ros ?? []) + [back])
                    .sorted { (ProjectDates.parse($0.startsAt) ?? .distantPast) < (ProjectDates.parse($1.startsAt) ?? .distantPast) }
            }
            return true
        }
        struct Params: Encodable {
            let pKind: String; let pId: String
            enum CodingKeys: String, CodingKey { case pKind = "p_kind", pId = "p_id" }
        }
        return await projectWrite("project_restore", Params(pKind: item.kind, pId: item.itemId))
    }

    @discardableResult
    func purgeProjectItem(_ item: ProjectTrashItem) async -> Bool {
        if projectOffline { ProjectDemo.trash.removeAll { $0.id == item.id }; return true }
        struct Params: Encodable {
            let pKind: String; let pId: String
            enum CodingKeys: String, CodingKey { case pKind = "p_kind", pId = "p_id" }
        }
        return await projectWrite("project_purge", Params(pKind: item.kind, pId: item.itemId), refresh: false)
    }

    // MARK: words

    /// "18:30" in the event's zone.
    func projectClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = projectSnapshot?.event?.timeZone ?? .current
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    func projectTrashKindName(_ kind: String) -> String {
        switch kind {
        case "task": return T("Việc", "Task")
        case "post": return T("Bài", "Post")
        case "ros": return T("Chương trình", "Run-of-show")
        default: return T("Hạng mục", "Lane")
        }
    }
}

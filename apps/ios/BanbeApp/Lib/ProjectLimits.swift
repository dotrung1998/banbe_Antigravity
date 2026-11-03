import Foundation

/// Event Project Hub limits (note 76). The numbers live in src/data/projectLimits.json, bundled as-is
/// (apps/ios/project.yml) and imported by the web (src/lib/projectPermissions.js). The server (migration 210)
/// enforces the same numbers. `ProjectLimitsTests` checks the bundled copy against the repo file.
struct ProjectLimits: Decodable, Equatable {
    let lanesMax: Int, laneNameMax: Int, changeWhyMax: Int
    let reasonMin: Int, reasonMax: Int
    let taskTitleMin: Int, taskTitleMax: Int
    let postTitleMin: Int, postTitleMax: Int, postBodyMax: Int, replyMax: Int, repliesMax: Int
    let proposalOptionsMin: Int, proposalOptionsMax: Int, proposalOptionMax: Int
    let rosTitleMin: Int, rosTitleMax: Int, rosMinMinutes: Int, rosWindowBeforeStartHours: Int, rosWindowAfterStartHours: Int
    let trashMax: Int, trashDays: Int
    let channelsMax: Int, channelLabelMax: Int, channelUrlMax: Int
    let inviteHours: Int, inviteMaxUses: Int
    let grantDays: Int, readOnlyDays: Int, purgeDays: Int, disputeGrantMaxDays: Int
    let proofOpenMinutes: Int, proofUrlSeconds: Int
    let pollSeconds: Int, digestHour: Int

    static let shared: ProjectLimits = {
        guard let url = Bundle.main.url(forResource: "projectLimits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let limits = try? JSONDecoder().decode(ProjectLimits.self, from: data) else {
            assertionFailure("projectLimits.json missing from the bundle — run xcodegen generate")
            return fallback
        }
        return limits
    }()

    /// Same numbers as the JSON, only used if the bundle is broken (a release build must still refuse safely).
    static let fallback = ProjectLimits(
        lanesMax: 10, laneNameMax: 24, changeWhyMax: 140, reasonMin: 3, reasonMax: 140, taskTitleMin: 3, taskTitleMax: 60,
        postTitleMin: 3, postTitleMax: 80, postBodyMax: 280, replyMax: 140, repliesMax: 10,
        proposalOptionsMin: 2, proposalOptionsMax: 4, proposalOptionMax: 40,
        rosTitleMin: 2, rosTitleMax: 40, rosMinMinutes: 10, rosWindowBeforeStartHours: 12, rosWindowAfterStartHours: 24,
        trashMax: 30, trashDays: 7, channelsMax: 5, channelLabelMax: 30, channelUrlMax: 300,
        inviteHours: 48, inviteMaxUses: 20, grantDays: 7, readOnlyDays: 30, purgeDays: 90, disputeGrantMaxDays: 30,
        proofOpenMinutes: 5, proofUrlSeconds: 60, pollSeconds: 15, digestHour: 18)
}

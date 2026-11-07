import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/onboardingVisuals.test.mjs (note 53) — change both together.
final class OnboardingVisualsTests: XCTestCase {
    func testEveryServerOptionHasItsOwnEmoji() {
        let lists = [EventPrefTaxonomy.interests, EventPrefTaxonomy.goals, EventPrefTaxonomy.availability, EventPrefTaxonomy.languages]
        let ids = lists.flatMap { $0.map(\.id) } + EventPrefTaxonomy.budgetTiers + [EventPrefTaxonomy.noPreference]
        for id in ids { XCTAssertNotNil(PrefEmoji.all[id], "\(id) has no emoji") }
        for list in lists {
            let faces = list.map { PrefEmoji.of($0.id) }
            XCTAssertEqual(Set(faces).count, faces.count)
        }
        XCTAssertEqual(Set(EventPrefTaxonomy.budgetTiers.map(PrefEmoji.of)).count, EventPrefTaxonomy.budgetTiers.count)
        XCTAssertEqual(PrefEmoji.of("unknown"), "•")
    }

    func testCategoriesMatchCreateEvent() {
        for o in EventPrefTaxonomy.interests { XCTAssertEqual(PrefEmoji.all[o.id], PrefEmoji.categories[o.id]) }
    }

    func testLiveFeedback() {
        typealias F = OnboardingFeedback
        XCTAssertNil(F.line(.interests, picked: [], vi: false))
        XCTAssertEqual(F.line(.interests, picked: ["music", "supper"], vi: false), "🎵 🍽️ · only these kinds get the ★")
        XCTAssertEqual(F.line(.goals, picked: ["learn"], vi: true), "💡 · sự kiện hợp sẽ được xếp lên trước")
        XCTAssertEqual(F.line(.availability, picked: [EventPrefTaxonomy.noPreference], vi: false), "🤷 · Nothing filtered here")
        XCTAssertEqual(F.line(.budget, picked: ["free"], vi: false), "🆓 · free events only")
        XCTAssertEqual(F.line(.budget, picked: ["medium"], vi: false), "💵 · hides events above this")
        XCTAssertEqual(F.line(.budget, picked: ["flexible"], vi: false), "💎 · no price limit")
        XCTAssertEqual(F.line(.languages, picked: ["vi"], vi: false), "🇻🇳 · saved, doesn't filter yet")
    }
}

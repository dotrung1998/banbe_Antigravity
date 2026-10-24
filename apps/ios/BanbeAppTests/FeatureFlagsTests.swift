import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/featureFlags.test.mjs — change both together.
final class FeatureFlagsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "FeatureFlagsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testMissingKeyMeansOnOnlyExplicitFalseHides() {
        XCTAssertTrue(FeatureFlags.isOn([:], "rewards"))
        XCTAssertTrue(FeatureFlags.isOn(["rewards": true], "rewards"))
        XCTAssertFalse(FeatureFlags.isOn(["rewards": false], "rewards"))
        XCTAssertTrue(FeatureFlags.isOn(["somethingElse": false], "rewards"))
    }

    func testNormalizeKeepsKnownBooleansOnly() {
        XCTAssertEqual(FeatureFlags.normalize(["rewards": false]), ["rewards": false])
        XCTAssertEqual(FeatureFlags.normalize(["rewards": nil]), [:])
        XCTAssertEqual(FeatureFlags.normalize(["somethingNew": false, "rewards": true]), ["rewards": true])
        XCTAssertEqual(FeatureFlags.normalize([:]), [:])
    }

    func testCacheRoundTripsAndSurvivesGarbage() {
        let d = freshDefaults()
        XCTAssertEqual(FeatureFlags.read(d), [:])
        FeatureFlags.write(["rewards": false], d)
        XCTAssertEqual(FeatureFlags.read(d), ["rewards": false])
        d.set(Data("{not json".utf8), forKey: FeatureFlags.cacheKey)
        XCTAssertEqual(FeatureFlags.read(d), [:])
        FeatureFlags.write(["rewards": true, "unknown": false], d)
        XCTAssertEqual(FeatureFlags.read(d), ["rewards": true], "unknown keys are never stored")
    }

    /// Note 54: the TESTING-PHASE wipe switch must never turn itself on — missing means OFF for it.
    func testWipeSwitchIsOffUnlessExplicitlyOn() {
        XCTAssertFalse(FeatureFlags.isOn([:], "admin_event_wipe"))
        XCTAssertFalse(FeatureFlags.isOn(["admin_event_wipe": false], "admin_event_wipe"))
        XCTAssertTrue(FeatureFlags.isOn(["admin_event_wipe": true], "admin_event_wipe"))
        XCTAssertTrue(FeatureFlags.isOn([:], "rewards"), "other flags keep missing = on")
    }

    /// Migration 201 (note 63): missing or false = onboarding Version 1, only an explicit true = Version 2.
    func testOnboardingV2IsVersionOneUnlessExplicitlyOn() {
        XCTAssertFalse(FeatureFlags.isOn([:], "onboarding_v2"))
        XCTAssertFalse(FeatureFlags.isOn(["onboarding_v2": false], "onboarding_v2"))
        XCTAssertTrue(FeatureFlags.isOn(["onboarding_v2": true], "onboarding_v2"))
        XCTAssertEqual(FeatureFlags.normalize(["onboarding_v2": true, "onboarding_v3": true]), ["onboarding_v2": true])
    }
}

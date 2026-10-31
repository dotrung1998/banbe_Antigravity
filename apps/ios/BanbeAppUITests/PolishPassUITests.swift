import XCTest

/// Note 53 polish pass, against the DEBUG fixtures (no network): Create event opens on Host with the recipe meter
/// already there, a recipe Fix lands ON the field (glow + tip + keyboard), the intro stays above the keyboard, and
/// onboarding answers are emoji tiles whose selected state is not the CTA's solid ink.
final class PolishPassUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchShell(_ variant: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", "en", "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreateOpensOnHostWithRecipeMeter() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10), "recipe meter is there from the first frame")
        XCTAssertTrue(el(app, "create.hostPrefilled").exists, "opens on step 1 (Host), already ticked")
        XCTAssertTrue(app.staticTexts["Looks good · Next: Basics"].exists || app.buttons["Looks good · Next: Basics"].exists)
        shot("create-host-step")
        el(app, "create.step.next").tap()
        XCTAssertTrue(el(app, "create.recipeMeter").exists)
        shot("create-basics-step")
    }

    func testRecipeFixLandsOnTheField() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        el(app, "create.recipeMeter").tap()
        XCTAssertTrue(el(app, "recipe.fix.keywords").waitForExistence(timeout: 5))
        el(app, "recipe.fix.keywords").tap()
        XCTAssertTrue(el(app, "create.coach").waitForExistence(timeout: 5), "the 👇 tip points at the field")
        sleep(1)
        shot("create-fix-keywords")
        if app.keyboards.count > 0 {
            let field = app.textFields["e.g. supper club, wine, Vietnamese food"]
            XCTAssertTrue(field.exists)
            XCTAssertLessThan(field.frame.maxY, app.keyboards.firstMatch.frame.minY, "the focused field is above the keyboard")
        }
    }

    func testIntroStaysAboveKeyboardWhileTyping() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        el(app, "create.step.next").tap()
        el(app, "create.substeps.1").tap()   // note 69: the intro is in Basics › Story
        let intro = el(app, "create.intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        intro.tap()
        sleep(1)
        intro.typeText("A cozy evening for sixteen strangers.\n\nThe main course is slow-braised pork.\nDoors at 19:30.")
        sleep(1)
        shot("create-intro-typing")
        if app.keyboards.count > 0 {
            XCTAssertLessThan(intro.frame.minY + 60, app.keyboards.firstMatch.frame.minY, "the intro's text is above the keyboard")
        }
    }

    func testOnboardingTilesAndFeedback() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "onboarding", "-banbe.lang", "en", "-uiTesting", "1", "-uiFixtureReset", "YES"]
        app.launch()
        XCTAssertTrue(el(app, "onboarding.start").waitForExistence(timeout: 10))
        shot("onboarding-welcome")
        el(app, "onboarding.start").tap()
        XCTAssertTrue(el(app, "onboarding.question.goals").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "onboarding.progress").label, "1 of 5")
        el(app, "onboarding.goals.learn").tap()
        XCTAssertTrue(el(app, "onboarding.goals.learn").isSelected)
        XCTAssertTrue(app.staticTexts["💡 · we'll rank events like this higher"].exists, "each tap answers")
        shot("onboarding-goals-selected")
    }

    /// Save draft → leave → the draft can be reopened from Drafts with what was typed.
    func testSaveDraftAndReopen() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        el(app, "create.step.next").tap()
        el(app, "create.substeps.1").tap()   // note 69: the intro is in Basics › Story
        let intro = el(app, "create.intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        intro.tap()
        intro.typeText("Draft text")
        el(app, "create.saveDraft").tap()
        // "Draft saved" card: start a new (blank) draft, then reopen the saved one from Drafts.
        XCTAssertTrue(el(app, "create.draftSaved").waitForExistence(timeout: 5), "Draft saved card")
        el(app, "create.draftSaved.new").tap()
        XCTAssertTrue(el(app, "create.drafts").waitForExistence(timeout: 5), "Drafts pill after saving")
        el(app, "create.drafts").tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'create.draft.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved draft is listed")
        row.tap()
        let story = el(app, "create.substeps.1")
        if story.waitForExistence(timeout: 3) { story.tap() }   // note 69: the intro is in Basics › Story
        XCTAssertTrue(el(app, "create.intro").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "create.intro").value as? String, "Draft text")
    }

    /// Owner report (2026-10-20): new event → type something → Back → Discard force-quit the app.
    func testLeavingCreateAfterTypingDoesNotCrash() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        el(app, "create.step.next").tap()
        el(app, "create.substeps.1").tap()   // note 69: the intro is in Basics › Story
        let intro = el(app, "create.intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        intro.tap()
        intro.typeText("Hello")
        app.buttons["‹ Back"].firstMatch.tap()
        // Leaving no longer asks "Discard?": it leaves and offers Undo at the bottom.
        let undo = el(app, "create.undo.button")
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo toast after leaving a draft with input")
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "still running after leaving Create")
        XCTAssertFalse(el(app, "create.recipeMeter").exists, "left Create")
        undo.tap()
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 5), "Undo reopens Create")
        if !el(app, "create.intro").exists, el(app, "create.substeps.1").exists { el(app, "create.substeps.1").tap() }
        XCTAssertEqual(el(app, "create.intro").value as? String, "Hello", "Undo keeps what was typed")
    }

    func testLeavingCreateWhileFieldFocusedDoesNotCrash() {
        let app = launchShell("create")
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        el(app, "create.step.next").tap()
        el(app, "create.substeps.1").tap()   // note 69: the intro is in Basics › Story
        let intro = el(app, "create.intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        intro.tap()
        intro.typeText("Hi")
        // Back while the keyboard is still up (no Done first).
        app.buttons["‹ Back"].firstMatch.tap()
        XCTAssertTrue(el(app, "create.undo.button").waitForExistence(timeout: 5), "Undo toast after leaving")
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The real "create a new event" entry, then every way back while there are changes.
    func testNewEventEditThenStepBackAndLeave() {
        let app = launchShell("createNew")
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        // Host step: type a host name, go to Basics, type, step back, step forward, leave.
        let hostName = app.textFields["Bếp Nhỏ"].firstMatch
        if hostName.waitForExistence(timeout: 3) { hostName.tap(); hostName.typeText("Mai") }
        el(app, "create.step.next").tap()
        let name = app.textFields["Your event name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Supper")
        el(app, "create.step.back").tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "step back with the keyboard up")
        el(app, "create.step.next").tap()
        el(app, "create.step.next").tap()
        sleep(1)
        el(app, "create.step.back").tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        // The sub-step bar makes Basics taller: scroll up so "‹ Back" is not under the sticky step bar.
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["‹ Back"].firstMatch.tap()
        XCTAssertTrue(el(app, "create.undo.button").waitForExistence(timeout: 5), "Undo toast after leaving")
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "still running after leaving Create")
        shot("after-leaving-create")
    }
}

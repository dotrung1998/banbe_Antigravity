import XCTest

/// The shared signed-in UI-test account, read from the environment at test time.
///
/// No credential is committed (audit 2026-11-19 row 5): the previous literals in
/// this target were a real login sitting in git history. Put the two values in the
/// gitignored `apps/ios/.env.uitest` and export them before a signed-in run:
///
///     set -a; source apps/ios/.env.uitest; set +a
///     xcodebuild test -project apps/ios/BanbeApp.xcodeproj -scheme BanbeApp ...
///
/// `TEST_RUNNER_`-prefixed copies are accepted too, since xcodebuild strips that
/// prefix when it hands the environment to the test runner.
enum UITestAccount {
    static let email = value("BANBE_UI_TEST_EMAIL")
    static let password = value("BANBE_UI_TEST_PASSWORD")

    static var isConfigured: Bool { !email.isEmpty && !password.isEmpty }

    /// Fails the calling test when the account is not configured. A signed-in test
    /// that quietly passes without a session would be worse than a red one.
    static func assertConfigured(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            isConfigured,
            "Set BANBE_UI_TEST_EMAIL and BANBE_UI_TEST_PASSWORD (apps/ios/.env.uitest) before running signed-in UI tests.",
            file: file, line: line
        )
    }

    private static func value(_ name: String) -> String {
        let env = ProcessInfo.processInfo.environment
        return (env[name] ?? env["TEST_RUNNER_\(name)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension XCUIApplication {
    /// Signed-out launches land on the public welcome screen (note 44), whose
    /// "Log in" opens Login in one tap. Waits for either and returns true
    /// once Login is showing; false if neither appears (already signed in).
    func reachLogin(timeout: TimeInterval) -> Bool {
        let login = otherElements["screen.login"]
        let welcomeLogin = descendants(matching: .any)["welcome.login"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if login.exists { return true }
            if welcomeLogin.exists {
                welcomeLogin.tap()
                return login.waitForExistence(timeout: 10)
            }
            if otherElements["screen.home"].exists { return false }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}

import XCTest

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

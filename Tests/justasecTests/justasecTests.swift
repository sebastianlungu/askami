import Testing
@testable import justasec

@Test("bundleIdentifier is com.sebastianlungu.justasec")
func bundleIdentifier() {
    #expect(JustasecApp.bundleIdentifier == "com.sebastianlungu.justasec")
}

@Test("validateDependencies succeeds with expected tools")
func validateDependencies() {
    let app = JustasecApp()
    let result = app.validateSystemDependencies()
    #expect(result)
}

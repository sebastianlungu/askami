import Testing
@testable import justasec

@Test("bundleIdentifier is com.sebastianlungu.justasec")
@MainActor
func bundleIdentifier() {
    #expect(JustasecApp.bundleIdentifier == "com.sebastianlungu.justasec")
}

@Test("validateDependencies succeeds with expected tools")
@MainActor
func validateDependencies() {
    let app = JustasecApp()
    let result = app.validateSystemDependencies()
    #expect(result)
}

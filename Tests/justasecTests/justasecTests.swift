import Testing
import Foundation
@testable import justasec

private var projectRoot: URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test("bundleIdentifier is com.sebastianlungu.justasec")
@MainActor
func bundleIdentifier() {
    #expect(JustasecApp.bundleIdentifier == "com.sebastianlungu.justasec")
}

@Test("activateDock is .regular for Dock visibility")
@MainActor
func activateDock() {
    #expect(JustasecApp.preferredActivationPolicy == .regular)
}

@Test("LSUIElement is false in Info.plist for Dock visibility")
@MainActor
func lsuiElementIsFalse() throws {
    let testFile = URL(filePath: #filePath)
    let plistPath = testFile
        .deletingLastPathComponent() // Tests/justasecTests
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root
        .appending(component: "scripts")
        .appending(component: "Info.plist")
    let data = try Data(contentsOf: plistPath)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    let dict = try #require(plist as? [String: Any])
    let lsui = dict["LSUIElement"]
    #expect(lsui == nil || (lsui as? Bool) == false)
}

@Test("AppIcon.icns exists in scripts directory")
@MainActor
func appIconExists() throws {
    let testFile = URL(filePath: #filePath)
    let iconPath = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(component: "scripts")
        .appending(component: "AppIcon.icns")
    let data = try Data(contentsOf: iconPath)
    #expect(data.count > 1024)
    let header = data.prefix(4)
    #expect(header == Data([0x69, 0x63, 0x6e, 0x73]))
}

@Test("build script bundles the Whisper model at the resolver path")
func buildScriptBundlesModel() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("Contents/Resources/models"))
    #expect(script.contains("models/ggml-base-q5_1.bin"))
}

@Test("validateDependencies succeeds with expected tools")
@MainActor
func validateDependencies() {
    let app = JustasecApp()
    let result = app.validateSystemDependencies()
    #expect(result)
}

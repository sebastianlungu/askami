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

@Test("activateDock is .accessory for menu-bar-only")
@MainActor
func activateDock() {
    #expect(JustasecApp.preferredActivationPolicy == .accessory)
}

@Test("LSUIElement is true in Info.plist for menu-bar-only")
@MainActor
func lsuiElementIsTrue() throws {
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
    #expect((lsui as? Bool) == true)
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

@Test("build script copies ready chime MP3 and validates hash")
func buildScriptCopiesReadyChime() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("ready-chime.mp3"))
    #expect(script.contains("3244c21a0ff72ab70cc2438a22f5e5655f0b11586063e7dded14cae51a6c6ac8"))
    #expect(!script.contains("sncf-sonic-logo.mp3"))
    #expect(!script.contains("success-chime.wav"))
    #expect(script.contains("shasum -a 256"))
}

@Test("build script no longer references old chime files")
func buildScriptNoOldChime() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(!script.contains("success-chime"))
    #expect(!script.contains("generate-success-chime"))
}

@Test("build script copies KokoroCoreML and BARTG2P resource bundles into app")
func buildScriptCopiesSwiftPMBundles() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("KokoroCoreML_KokoroCoreML.bundle"))
    #expect(script.contains("swift-bart-g2p_BARTG2P.bundle"))
    #expect(script.contains("Contents/Resources/"))
    let hasReleaseDir = script.contains("RELEASE_DIR=") || script.contains("RELEASE_DIR=\"")
    #expect(hasReleaseDir, "build.sh must define RELEASE_DIR as single source of truth")
}

@Test("build script uses the stable JustASec signing identity with hardened runtime")
func buildScriptUsesStableSigning() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("JustASec Dev"))
    #expect(script.contains("--sign \"$SIGN_IDENTITY\""))
    #expect(!script.contains("--sign -"))
    #expect(script.contains("--options runtime"))
    #expect(script.contains("basicConstraints=critical,CA:FALSE"))
}

@Test("build script provisions ECDSA P-256 identity, not RSA 2048")
func buildScriptUsesP256Signing() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("prime256v1"), "must use EC P-256 curve")
    #expect(!script.contains("rsa:2048"), "must NOT use RSA 2048")
}

@Test("install script resets capture permissions only after an identity change")
func installScriptHandlesSigningMigration() throws {
    let scriptURL = projectRoot.appending(path: "scripts/install.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("app_uses_expected_identity"))
    #expect(script.contains("tccutil reset Microphone"))
    #expect(script.contains("tccutil reset AudioCapture"))
}

@Test("sign skill delegates to the stable install workflow")
func signSkillUsesInstallScript() throws {
    let skillURL = projectRoot.appending(path: ".opencode/skills/sign/SKILL.md")
    let skill = try String(contentsOf: skillURL, encoding: .utf8)
    #expect(skill.contains("bash scripts/install.sh"))
}

@Test("validateDependencies succeeds with expected tools")
@MainActor
func validateDependencies() {
    let app = JustasecApp()
    let result = app.validateSystemDependencies()
    #expect(result)
}

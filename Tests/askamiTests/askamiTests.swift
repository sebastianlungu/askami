import Testing
import Foundation
@testable import askami

private var projectRoot: URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test("bundleIdentifier is com.sebastianlungu.askami")
@MainActor
func bundleIdentifier() {
    #expect(AskamiApp.bundleIdentifier == "com.sebastianlungu.askami")
}

@Test("activateDock is .accessory for menu-bar-only")
@MainActor
func activateDock() {
    #expect(AskamiApp.preferredActivationPolicy == .accessory)
}

@Test("LSUIElement is true in Info.plist for menu-bar-only")
@MainActor
func lsuiElementIsTrue() throws {
    let testFile = URL(filePath: #filePath)
    let plistPath = testFile
        .deletingLastPathComponent() // Tests/askamiTests
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
    #expect(script.contains("e0c00388d3a91f11721ac5ed3070db67c230e0ed0d98022f3a5a31588434d472"))
    #expect(!script.contains("sncf-sonic-logo.mp3"))
    #expect(!script.contains("success-chime.wav"))
    #expect(script.contains("shasum -a 256"))
}

@Test("successful speech completion has no artificial settle")
func successfulSpeechHasNoSettle() throws {
    let sourceURL = projectRoot.appending(path: "Sources/askami/PipelineOrchestrator.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let function = try #require(source.components(separatedBy: "completeSuccessfulSpeech").last)
    #expect(function.contains("endSuppression(after: 0)"))
    #expect(!function.contains("endSuppression(after: 0.5)"))
}

@Test("ready chime plays at 0.8 volume")
func readyChimeVolume() throws {
    let sourceURL = projectRoot.appending(path: "Sources/askami/AudioFeedback.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(source.contains("player.volume = 0.8"))
}

@Test("speech announcement waits for prepared TTS audio")
func speechAnnouncementUsesPlaybackBoundary() throws {
    let sourceURL = projectRoot.appending(path: "Sources/askami/PipelineOrchestrator.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(source.contains("beforePlayback:"))

    let speechURL = projectRoot.appending(path: "Sources/askami/SpeechSynthesizer.swift")
    let speechSource = try String(contentsOf: speechURL, encoding: .utf8)
    #expect(speechSource.contains("guard hasAudio else"))
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

@Test("build script uses the stable Askami signing identity with hardened runtime")
func buildScriptUsesStableSigning() throws {
    let scriptURL = projectRoot.appending(path: "scripts/build.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("Askami Dev"))
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

@Test("validateDependencies succeeds with expected tools", .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/opencode")))
@MainActor
func validateDependencies() {
    let app = AskamiApp()
    let result = app.validateSystemDependencies()
    #expect(result)
}

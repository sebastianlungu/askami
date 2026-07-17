import Foundation

public struct JustasecApp {
    public static let bundleIdentifier: String = "com.sebastianlungu.justasec"

    private static let requiredTools: [(name: String, path: String, arg: String)] = [
        ("swift", "/usr/bin/swift", "--version"),
        ("xcodebuild", "/usr/bin/xcodebuild", "-version"),
        ("opencode", "/opt/homebrew/bin/opencode", "--version"),
        ("whisper-server", "/opt/homebrew/bin/whisper-server", "--help"),
    ]

    public init() {}

    public func validateSystemDependencies() -> Bool {
        Self.requiredTools.allSatisfy { tool in
            checkToolAvailable(at: tool.path, with: tool.arg)
        }
    }

    private func checkToolAvailable(at path: String, with argument: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [argument]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

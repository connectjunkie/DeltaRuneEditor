import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Whether DELTARUNE is currently running.
///
/// This matters because the game holds its save state in memory and writes it out on its
/// own schedule — anything we change while it's open gets overwritten the next time the
/// player saves. Behind a protocol so tests can force either answer.
public protocol GameRunningChecking: Sendable {
    var isGameRunning: Bool { get }
}

public struct GameRunningMonitor: GameRunningChecking {
    /// Bundle identifiers and process names the game is known to use.
    static let bundleIdentifiers: Set<String> = [
        "com.tobyfox.deltarune",
        "com.tobyfox.deltarune.demo",
    ]
    static let processNames: Set<String> = ["deltarune", "DELTARUNE"]

    public init() {}

    public var isGameRunning: Bool {
        #if canImport(AppKit)
        NSWorkspace.shared.runningApplications.contains { app in
            if let identifier = app.bundleIdentifier?.lowercased(),
               Self.bundleIdentifiers.contains(identifier) {
                return true
            }
            if let name = app.localizedName,
               Self.processNames.contains(where: { name.caseInsensitiveCompare($0) == .orderedSame }) {
                return true
            }
            return false
        }
        #else
        false
        #endif
    }
}

/// Always reports the answer it was given. Test-only stand-in.
public struct StubGameMonitor: GameRunningChecking {
    public let isGameRunning: Bool
    public init(isRunning: Bool) { self.isGameRunning = isRunning }
}

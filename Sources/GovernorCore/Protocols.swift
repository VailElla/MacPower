public enum PowerSystemClientFailure: Error, Equatable, Sendable {
    case permissionDenied
    case readFailed
    case requestFailed
}

public protocol PowerSystemClient: Sendable {
    /// Performs the single, user-initiated authorization interaction for this app session.
    func authorize() async throws

    func readSnapshot() async throws -> PowerSnapshot

    /// Requests a mode for the current source and syntax captured in the preceding read.
    func requestMode(
        _ mode: PowerMode,
        source: PowerSource,
        controlStyle: PowerControlStyle
    ) async throws
}

public extension PowerSystemClient {
    func authorize() async throws {}
}

/// User-selected brightness values captured before entering Low Power.
///
/// Display identifiers are session-local Core Graphics IDs. The core target
/// deliberately stores only opaque identifiers and normalized values so the
/// platform-specific implementation remains in the macOS app target.
public struct DisplayBrightnessSnapshot: Equatable, Sendable {
    public let levelsByDisplayID: [UInt32: Float]

    public init(levelsByDisplayID: [UInt32: Float]) {
        self.levelsByDisplayID = levelsByDisplayID
    }
}

/// Best-effort display brightness access used around Low Power transitions.
///
/// Brightness support must never become a prerequisite for power-mode control:
/// an unavailable display API returns `nil`, and restore failures are ignored.
public protocol DisplayBrightnessClient: Sendable {
    func captureCurrentBrightness() async -> DisplayBrightnessSnapshot?
    func restoreBrightness(
        _ snapshot: DisplayBrightnessSnapshot,
        after delayMilliseconds: Int
    ) async
}

public struct NoOpDisplayBrightnessClient: DisplayBrightnessClient {
    public init() {}

    public func captureCurrentBrightness() async -> DisplayBrightnessSnapshot? { nil }

    public func restoreBrightness(
        _ snapshot: DisplayBrightnessSnapshot,
        after delayMilliseconds: Int
    ) async {}
}

public protocol SwitchHistoryStore: Sendable {
    func loadHistory() async throws -> [SwitchHistoryEntry]
    func saveHistory(_ history: [SwitchHistoryEntry]) async throws
}

public struct NoOpSwitchHistoryStore: SwitchHistoryStore {
    public init() {}

    public func loadHistory() async throws -> [SwitchHistoryEntry] { [] }

    public func saveHistory(_ history: [SwitchHistoryEntry]) async throws {}
}

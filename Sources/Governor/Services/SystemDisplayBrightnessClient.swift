import CoreGraphics
import Darwin
import Foundation
import GovernorCore

/// Captures and restores the built-in display's user brightness around Low
/// Power transitions.
///
/// Apple exposes the required entry points from DisplayServices on current
/// macOS releases but does not ship public Swift headers for them. Resolve the
/// functions dynamically so absence or signature removal degrades to a no-op
/// instead of preventing Governor from launching.
actor SystemDisplayBrightnessClient: DisplayBrightnessClient {
    private let api = DisplayServicesBrightnessAPI.load()

    func captureCurrentBrightness() -> DisplayBrightnessSnapshot? {
        guard let api else { return nil }

        var levels: [UInt32: Float] = [:]
        for displayID in Self.onlineBuiltInDisplayIDs() {
            var brightness: Float = 0
            guard api.getBrightness(displayID, &brightness) == 0,
                  brightness.isFinite,
                  (0 ... 1).contains(brightness)
            else {
                continue
            }
            levels[displayID] = brightness
        }

        guard !levels.isEmpty else { return nil }
        return DisplayBrightnessSnapshot(levelsByDisplayID: levels)
    }

    func restoreBrightness(
        _ snapshot: DisplayBrightnessSnapshot,
        after delayMilliseconds: Int
    ) async {
        guard let api else { return }

        // pmset confirms the new mode before this method runs. The configured delay
        // lets the display power policy finish applying that transition before
        // the saved user value is restored.
        let clampedDelay = AutomationConfig.clampedBrightnessRestoreDelay(
            delayMilliseconds
        )
        if clampedDelay > 0 {
            try? await Task.sleep(for: .milliseconds(clampedDelay))
        }

        let onlineDisplayIDs = Set(Self.onlineBuiltInDisplayIDs())
        for (displayID, brightness) in snapshot.levelsByDisplayID
        where onlineDisplayIDs.contains(displayID) {
            _ = api.setBrightness(displayID, brightness)
        }
    }

    private static func onlineBuiltInDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
    }
}

private final class DisplayServicesBrightnessAPI: @unchecked Sendable {
    typealias GetBrightness = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let handle: UnsafeMutableRawPointer
    let getBrightness: GetBrightness
    let setBrightness: SetBrightness

    private init(
        handle: UnsafeMutableRawPointer,
        getBrightness: @escaping GetBrightness,
        setBrightness: @escaping SetBrightness
    ) {
        self.handle = handle
        self.getBrightness = getBrightness
        self.setBrightness = setBrightness
    }

    deinit {
        dlclose(handle)
    }

    static func load() -> DisplayServicesBrightnessAPI? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            dlclose(handle)
            return nil
        }

        return DisplayServicesBrightnessAPI(
            handle: handle,
            getBrightness: unsafeBitCast(getSymbol, to: GetBrightness.self),
            setBrightness: unsafeBitCast(setSymbol, to: SetBrightness.self)
        )
    }
}

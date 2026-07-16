import AppKit
import SwiftUI

@MainActor
final class AppLifecycle {
    static let shared = AppLifecycle()

    static let automationSettingsMinimumContentSize = NSSize(width: 500, height: 320)
    static let automationSettingsPreferredContentSize = NSSize(width: 500, height: 760)
    private static let automationSettingsScreenMargin: CGFloat = 48

    weak var model: AppModel?
    private var automationSettingsWindow: NSWindow?

    private init() {}

    /// The settings window belongs to the application lifecycle, not to a
    /// transient menu-bar view or delegate lookup. Deferring the presentation
    /// lets the menu-bar popover finish its dismissal before AppKit makes the
    /// new window key and visible.
    func showAutomationSettings() {
        guard let model else { return }

        let window: NSWindow
        if let automationSettingsWindow {
            window = automationSettingsWindow
        } else {
            let controller = NSHostingController(
                rootView: AutomationSettingsWindowContent(model: model)
            )
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = automationSettingsWindowTitle
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.contentMinSize = Self.automationSettingsMinimumContentSize
            newWindow.setContentSize(
                Self.automationSettingsInitialContentSize(
                    for: NSScreen.main?.visibleFrame
                )
            )
            newWindow.collectionBehavior = [.moveToActiveSpace]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            automationSettingsWindow = newWindow
            window = newWindow
        }

        window.title = automationSettingsWindowTitle
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func updateAutomationSettingsWindowTitle(for language: AppLanguage? = nil) {
        automationSettingsWindow?.title = AppText.automationSettingsTitle(
            language ?? LanguageSettings.shared.language
        )
    }

    static func automationSettingsInitialContentSize(for visibleFrame: NSRect?) -> NSSize {
        guard let visibleFrame else {
            return automationSettingsPreferredContentSize
        }

        let maximumContentHeight = max(
            automationSettingsMinimumContentSize.height,
            visibleFrame.height - automationSettingsScreenMargin
        )
        return NSSize(
            width: automationSettingsPreferredContentSize.width,
            height: min(
                automationSettingsPreferredContentSize.height,
                maximumContentHeight
            )
        )
    }

    private var automationSettingsWindowTitle: String {
        AppText.automationSettingsTitle(LanguageSettings.shared.language)
    }
}

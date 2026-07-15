import AppKit
import SwiftUI

@MainActor
final class AppLifecycle {
    static let shared = AppLifecycle()

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
                rootView: AutomationSettingsView(model: model)
            )
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = automationSettingsWindowTitle
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 500, height: 760))
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

    private var automationSettingsWindowTitle: String {
        AppText.automationSettingsTitle(LanguageSettings.shared.language)
    }
}

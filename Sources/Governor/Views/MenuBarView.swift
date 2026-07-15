import AppKit
import GovernorCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var languageSettings = LanguageSettings.shared

    private var language: AppLanguage { languageSettings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    title: AppText.currentPowerMode(language),
                    value: model.actualModeText
                )
                StatusRow(
                    title: AppText.automationStatus(language),
                    value: model.automationStatusText
                )
                StatusRow(
                    title: AppText.lastSwitchReason(language),
                    value: model.lastSwitchReasonText
                )
            }

            Divider()

            Toggle(AppText.automation(language), isOn: automationBinding)

            if model.requiresHelperApproval {
                Button(AppText.openLoginItemsSettings(language)) {
                    model.openHelperApprovalSettings()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                DispatchQueue.main.async {
                    AppLifecycle.shared.showAutomationSettings()
                }
            } label: {
                Label(
                    AppText.automationSettings(language),
                    systemImage: "gearshape"
                )
            }
            .accessibilityHint(AppText.automationSettingsHint(language))

            if model.isPaused {
                Button(AppText.resumeAutomation(language)) {
                    model.resumeAutomation()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(AppText.quit(language)) {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AppVersion.displayText(in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(AppVersion.displayText(in: language))
        }
        .padding(14)
        .frame(width: 320)
    }

    private var automationBinding: Binding<Bool> {
        Binding(
            get: { model.isAutomationEnabled },
            set: { model.setAutomationEnabled($0) }
        )
    }
}

import GovernorCore
import SwiftUI

/// A full settings window keeps the menu-bar popover focused on status and the
/// main switch, while presenting the automation rule as a short, readable flow.
struct AutomationSettingsWindowContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.vertical) {
            AutomationSettingsView(model: model)
                .frame(minWidth: 500, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500)
    }
}

struct AutomationSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @State private var isShowingResetConfirmation = false

    private var language: AppLanguage { languageSettings.language }

    var body: some View {
        Form {
            Section(AppText.language(language)) {
                Picker(AppText.language(language), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.selectionTitle).tag(option)
                    }
                }
            }

            Section(AppText.automationStatus(language)) {
                Toggle(AppText.enableAutomation(language), isOn: automationBinding)
                    .disabled(model.persistentHelperUnavailableInCurrentBuild)
                LabeledContent(AppText.currentStatus(language)) {
                    Text(model.automationStatusText)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(AppText.currentPowerMode(language)) {
                    Text(model.actualModeText)
                        .foregroundStyle(.secondary)
                }
                if model.usesSessionAuthorizationInCurrentBuild {
                    Text(AppText.sessionAuthorizationRequired(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.persistentHelperUnavailableInCurrentBuild {
                    Text(AppText.unnotarizedHelperUnavailable(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.requiresHelperApproval {
                    Text(AppText.helperApprovalRequired(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(AppText.openLoginItemsSettings(language)) {
                        model.openHelperApprovalSettings()
                    }
                }
            }

            Section {
                HStack {
                    Text(AppText.afterNoInputFor(language))
                    Spacer()
                    TextField(
                        AppText.idleTime(language),
                        value: idleTimeValueBinding,
                        format: .number
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .accessibilityLabel(AppText.idleTime(language))

                    Stepper("", value: idleTimeValueBinding, in: 1 ... 86_400)
                        .labelsHidden()
                        .accessibilityLabel(AppText.adjustIdleTime(language))

                    Picker(AppText.timeUnit(language), selection: idleTimeUnitBinding) {
                        ForEach(IdleTimeUnit.allCases, id: \.self) { unit in
                            Text(unit.displayText(in: language)).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(AppText.idleTimeUnit(language))
                }

                powerModePicker(
                    title: AppText.thenSwitchTo(language),
                    selection: idlePowerModeBinding
                )

                pollingIntervalControl(
                    title: AppText.idleCheckInterval(language),
                    value: idlePollingIntervalValueBinding,
                    unit: idlePollingIntervalUnitBinding,
                    units: PollingIntervalUnit.idleOptions
                )
            } header: {
                settingsSectionHeader(
                    AppText.switchAfterInactivity(language),
                    helpText: AppText.idleExplanation(
                        duration: idleDurationDescription,
                        language: language
                    )
                )
            }

            Section {
                powerModePicker(
                    title: AppText.usePowerMode(language),
                    selection: activePowerModeBinding
                )

                pollingIntervalControl(
                    title: AppText.activeCheckInterval(language),
                    value: activePollingIntervalValueBinding,
                    unit: activePollingIntervalUnitBinding,
                    units: PollingIntervalUnit.activeOptions
                )
            } header: {
                settingsSectionHeader(
                    AppText.active(language),
                    helpText: AppText.pollingIntervalHelp(language)
                )
            }

            Section(AppText.idleProtection(language)) {
                Toggle(
                    AppText.pauseAfterManualChange(language),
                    isOn: pauseOnManualPowerModeChangeBinding
                )
                .accessibilityHint(AppText.pauseAfterManualChangeHint(language))

                if model.isPaused {
                    Button(AppText.resumeAutomation(language)) {
                        model.resumeAutomation()
                    }
                }
            }

            Section(AppText.brightnessRestoration(language)) {
                Toggle(
                    AppText.restoreBrightness(language),
                    isOn: restoreBrightnessAfterLowPowerBinding
                )
                .accessibilityHint(AppText.restoreBrightnessHint(language))

                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(
                            AppText.waitTime(language),
                            value: brightnessRestoreDelayBinding,
                            format: .number
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .accessibilityLabel(AppText.brightnessRestoreDelay(language))

                        Stepper(
                            "",
                            value: brightnessRestoreDelayBinding,
                            in: AutomationConfig.brightnessRestoreDelayRange
                        )
                        .labelsHidden()
                        .accessibilityLabel(AppText.adjustBrightnessRestoreDelay(language))

                        Text(PollingIntervalUnit.milliseconds.displayText(in: language))
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(AppText.waitBeforeRestoring(language))
                        settingsInfoIcon(AppText.brightnessDelayHelp(language))
                    }
                }
                .disabled(!model.restoreBrightnessAfterLowPower)
            }

            Section(AppText.settingsManagement(language)) {
                HStack(spacing: 4) {
                    Button(AppText.restoreDefaults(language)) {
                        isShowingResetConfirmation = true
                    }
                    settingsInfoIcon(AppText.restoreDefaultsHelp(language))
                }
            }

            if !model.isHighPowerCurrentlyAvailable {
                Text(AppText.highPowerUnavailable(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            AppText.restoreDefaultsConfirmation(language),
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppText.restoreDefaults(language), role: .destructive) {
                model.restoreDefaultSettings()
            }
            Button(AppText.cancel(language), role: .cancel) {}
        } message: {
            Text(AppText.restoreDefaultsMessage(language))
        }
    }

    private var automationBinding: Binding<Bool> {
        Binding(
            get: { model.isAutomationEnabled },
            set: { model.setAutomationEnabled($0) }
        )
    }

    private func settingsSectionHeader(
        _ title: String,
        helpText: String
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
            settingsInfoIcon(helpText)
        }
    }

    private func settingsInfoIcon(_ helpText: String) -> some View {
        Image(systemName: "info.circle")
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { languageSettings.language },
            set: { selectedLanguage in
                languageSettings.select(selectedLanguage)
                AppLifecycle.shared.updateAutomationSettingsWindowTitle()
            }
        )
    }

    private var idleTimeValueBinding: Binding<Int> {
        Binding(
            get: { model.idleTimeValue },
            set: { model.setIdleTimeValue($0) }
        )
    }

    private var idleTimeUnitBinding: Binding<IdleTimeUnit> {
        Binding(
            get: { model.idleTimeUnit },
            set: { model.setIdleTimeUnit($0) }
        )
    }

    private var idleDurationDescription: String {
        "\(model.idleTimeValue) \(model.idleTimeUnit.displayText(in: language))"
    }

    private var activePollingIntervalValueBinding: Binding<Double> {
        Binding(
            get: { model.activePollingIntervalValue },
            set: { model.setActivePollingIntervalValue($0) }
        )
    }

    private var activePollingIntervalUnitBinding: Binding<PollingIntervalUnit> {
        Binding(
            get: { model.activePollingIntervalUnit },
            set: { model.setActivePollingIntervalUnit($0) }
        )
    }

    private var idlePollingIntervalValueBinding: Binding<Double> {
        Binding(
            get: { model.idlePollingIntervalValue },
            set: { model.setIdlePollingIntervalValue($0) }
        )
    }

    private var idlePollingIntervalUnitBinding: Binding<PollingIntervalUnit> {
        Binding(
            get: { model.idlePollingIntervalUnit },
            set: { model.setIdlePollingIntervalUnit($0) }
        )
    }

    private var activePowerModeBinding: Binding<PowerMode> {
        Binding(
            get: { model.activePowerMode },
            set: { model.setActivePowerMode($0) }
        )
    }

    private var idlePowerModeBinding: Binding<PowerMode> {
        Binding(
            get: { model.idlePowerMode },
            set: { model.setIdlePowerMode($0) }
        )
    }

    private var pauseOnManualPowerModeChangeBinding: Binding<Bool> {
        Binding(
            get: { model.pauseOnManualPowerModeChange },
            set: { model.setPauseOnManualPowerModeChange($0) }
        )
    }

    private var restoreBrightnessAfterLowPowerBinding: Binding<Bool> {
        Binding(
            get: { model.restoreBrightnessAfterLowPower },
            set: { model.setRestoreBrightnessAfterLowPower($0) }
        )
    }

    private var brightnessRestoreDelayBinding: Binding<Int> {
        Binding(
            get: { model.brightnessRestoreDelayMilliseconds },
            set: { model.setBrightnessRestoreDelayMilliseconds($0) }
        )
    }

    private func powerModePicker(
        title: String,
        selection: Binding<PowerMode>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(PowerMode.allCases, id: \.rawValue) { mode in
                Text(powerModeOptionText(mode)).tag(mode)
            }
        }
    }

    private func pollingIntervalControl(
        title: String,
        value: Binding<Double>,
        unit: Binding<PollingIntervalUnit>,
        units: [PollingIntervalUnit]
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(
                    AppText.checkInterval(language),
                    value: value,
                    format: .number.precision(.fractionLength(0 ... 4))
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
                .accessibilityLabel(title)

                Picker(AppText.timeUnit(language), selection: unit) {
                    ForEach(units, id: \.self) { option in
                        Text(option.displayText(in: language)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel(AppText.checkIntervalUnit(language, title: title))
            }
        }
    }

    private func powerModeOptionText(_ mode: PowerMode) -> String {
        guard mode == .highPower, !model.isHighPowerCurrentlyAvailable else {
            return mode.displayText(in: language)
        }
        return AppText.unavailableHighPowerOption(language)
    }
}

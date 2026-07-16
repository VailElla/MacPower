import Foundation

enum AppText {
    static let productName = "Governor"

    static func choose(
        _ language: AppLanguage,
        english: String,
        chinese: String
    ) -> String {
        language == .chinese ? chinese : english
    }

    static func language(_ language: AppLanguage) -> String {
        choose(language, english: "Language", chinese: "语言")
    }

    static func automationStatus(_ language: AppLanguage) -> String {
        choose(language, english: "Automation status", chinese: "自动切换状态")
    }

    static func enableAutomation(_ language: AppLanguage) -> String {
        choose(language, english: "Enable automation", chinese: "启用自动切换")
    }

    static func currentStatus(_ language: AppLanguage) -> String {
        choose(language, english: "Current status", chinese: "当前状态")
    }

    static func currentPowerMode(_ language: AppLanguage) -> String {
        choose(language, english: "Current power mode", chinese: "当前电源模式")
    }

    static func helperApprovalRequired(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Approve Governor's power helper once in Login Items before enabling automation. Later launches and lock/unlock do not require another password.",
            chinese: "请先在“登录项”中一次性批准 Governor 的电源 Helper；之后重新打开应用或锁屏解锁都不再需要输入密码。"
        )
    }

    static func openLoginItemsSettings(_ language: AppLanguage) -> String {
        choose(language, english: "Open Login Items Settings", chinese: "打开“登录项”设置")
    }

    static func unnotarizedHelperUnavailable(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "This build has no usable power authorization path.",
            chinese: "当前安装包没有可用的电源授权方式。"
        )
    }

    static func sessionAuthorizationRequired(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "This manual-install build asks for administrator authorization once when you enable automation. It expires when Governor quits and does not appear in Login Items.",
            chinese: "当前手动安装包会在启用自动切换时请求一次管理员授权；关闭 Governor 后授权失效，下次重新打开需再次授权，也不会出现在“登录项”。"
        )
    }

    static func switchAfterInactivity(_ language: AppLanguage) -> String {
        choose(language, english: "Switch after inactivity", chinese: "用户空闲后切换")
    }

    static func afterNoInputFor(_ language: AppLanguage) -> String {
        choose(language, english: "After no input for", chinese: "连续无操作达到")
    }

    static func idleTime(_ language: AppLanguage) -> String {
        choose(language, english: "Idle time", chinese: "连续无操作时间")
    }

    static func timeUnit(_ language: AppLanguage) -> String {
        choose(language, english: "Time unit", chinese: "时间单位")
    }

    static func adjustIdleTime(_ language: AppLanguage) -> String {
        choose(language, english: "Adjust idle time", chinese: "调整连续无操作时间")
    }

    static func idleTimeUnit(_ language: AppLanguage) -> String {
        choose(language, english: "Idle time unit", chinese: "连续无操作时间单位")
    }

    static func idleExplanation(
        duration: String,
        language: AppLanguage
    ) -> String {
        choose(
            language,
            english: "When no keyboard, mouse, or trackpad input is detected for \(duration), Governor switches to the power mode selected below.",
            chinese: "当系统连续 \(duration) 没有检测到键盘、鼠标或触控板操作时，Governor 会切换到下方选择的电源模式。"
        )
    }

    static func thenSwitchTo(_ language: AppLanguage) -> String {
        choose(language, english: "Then switch to", chinese: "随后切换到")
    }

    static func idleCheckInterval(_ language: AppLanguage) -> String {
        choose(language, english: "Idle check interval", chinese: "空闲时检测间隔")
    }

    static func active(_ language: AppLanguage) -> String {
        choose(language, english: "When active", chinese: "活跃时")
    }

    static func usePowerMode(_ language: AppLanguage) -> String {
        choose(language, english: "Use power mode", chinese: "使用电源模式")
    }

    static func activeCheckInterval(_ language: AppLanguage) -> String {
        choose(language, english: "Active check interval", chinese: "活跃时检测间隔")
    }

    static func checkInterval(_ language: AppLanguage) -> String {
        choose(language, english: "Check interval", chinese: "检测间隔")
    }

    static func checkIntervalUnit(_ language: AppLanguage, title: String) -> String {
        choose(language, english: "\(title) unit", chinese: "\(title)单位")
    }

    static func pollingIntervalHelp(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Intervals can range from 100 milliseconds to 3600 seconds; active checks can also use minutes.",
            chinese: "检测间隔可设为 100 毫秒至 3600 秒；活跃时也可使用分钟。"
        )
    }

    static func idleProtection(_ language: AppLanguage) -> String {
        choose(language, english: "Idle protection", chinese: "空闲保护")
    }

    static func pauseAfterManualChange(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Pause automation after a manual power mode change",
            chinese: "手动切换后暂停自动切换"
        )
    }

    static func pauseAfterManualChangeHint(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Pause automation when the system power mode changes outside Governor.",
            chinese: "检测到系统电源模式被外部修改时暂停自动切换。"
        )
    }

    static func resumeAutomation(_ language: AppLanguage) -> String {
        choose(language, english: "Resume automation", chinese: "恢复自动切换")
    }

    static func brightnessRestoration(_ language: AppLanguage) -> String {
        choose(language, english: "Brightness restoration", chinese: "亮度恢复")
    }

    static func restoreBrightness(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Restore brightness after leaving Low Power",
            chinese: "退出低电量模式后恢复亮度"
        )
    }

    static func restoreBrightnessHint(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Restore the built-in display brightness that was saved before entering Low Power.",
            chinese: "恢复进入低电量模式前保存的内建屏幕亮度。"
        )
    }

    static func waitBeforeRestoring(_ language: AppLanguage) -> String {
        choose(language, english: "Wait before restoring", chinese: "恢复前等待")
    }

    static func waitTime(_ language: AppLanguage) -> String {
        choose(language, english: "Wait time", chinese: "等待时间")
    }

    static func brightnessRestoreDelay(_ language: AppLanguage) -> String {
        choose(language, english: "Brightness restoration delay", chinese: "亮度恢复等待时间")
    }

    static func adjustBrightnessRestoreDelay(_ language: AppLanguage) -> String {
        choose(language, english: "Adjust brightness restoration delay", chinese: "调整亮度恢复等待时间")
    }

    static func brightnessDelayHelp(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "The default is 0 milliseconds. If restoration does not happen, increase the delay.",
            chinese: "默认 0 毫秒；如果没有恢复，可以延长等待时间。"
        )
    }

    static func settingsManagement(_ language: AppLanguage) -> String {
        choose(language, english: "Settings management", chinese: "设置管理")
    }

    static func restoreDefaults(_ language: AppLanguage) -> String {
        choose(language, english: "Restore default settings", chinese: "恢复默认设置")
    }

    static func restoreDefaultsHelp(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Restore all rules and options. The current automation switch is unchanged.",
            chinese: "恢复所有规则与选项；当前自动化开关保持不变。"
        )
    }

    static func restoreDefaultsConfirmation(_ language: AppLanguage) -> String {
        choose(language, english: "Restore default settings?", chinese: "恢复默认设置？")
    }

    static func restoreDefaultsMessage(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Idle time, check intervals, power modes, and brightness options will be restored.",
            chinese: "空闲时间、检测间隔、电源模式和亮度选项将恢复默认值。"
        )
    }

    static func cancel(_ language: AppLanguage) -> String {
        choose(language, english: "Cancel", chinese: "取消")
    }

    static func highPowerUnavailable(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "This Mac or power state does not support High Power. Choosing it uses Automatic instead.",
            chinese: "当前设备或供电状态不支持高性能模式；选择它时会自动使用自动模式。"
        )
    }

    static func unavailableHighPowerOption(_ language: AppLanguage) -> String {
        choose(language, english: "High Power (currently unavailable)", chinese: "高性能（当前不可用）")
    }

    static func automationSettingsTitle(_ language: AppLanguage) -> String {
        choose(language, english: "Automation", chinese: "自动切换")
    }

    static func lastSwitchReason(_ language: AppLanguage) -> String {
        choose(language, english: "Last switch reason", chinese: "最近一次切换原因")
    }

    static func automation(_ language: AppLanguage) -> String {
        choose(language, english: "Automation", chinese: "自动化")
    }

    static func automationSettings(_ language: AppLanguage) -> String {
        choose(language, english: "Automation settings…", chinese: "自动切换设置…")
    }

    static func automationSettingsHint(_ language: AppLanguage) -> String {
        choose(
            language,
            english: "Open detailed automation power settings.",
            chinese: "打开自动电源切换的详细设置。"
        )
    }

    static func quit(_ language: AppLanguage) -> String {
        choose(language, english: "Quit Governor", chinese: "退出 Governor")
    }

    static func versionAccessibility(
        version: String,
        releaseName: String,
        language: AppLanguage
    ) -> String {
        choose(
            language,
            english: "Version \(version), \(releaseName)",
            chinese: "版本 \(version)，\(releaseName)"
        )
    }

    static func unknown(_ language: AppLanguage) -> String {
        choose(language, english: "Unknown", chinese: "未知")
    }

    static func none(_ language: AppLanguage) -> String {
        choose(language, english: "None", chinese: "暂无")
    }

    static func developmentBuild(_ language: AppLanguage) -> String {
        choose(language, english: "Development build", chinese: "开发构建")
    }

    static func unmarkedRelease(_ language: AppLanguage) -> String {
        choose(language, english: "Unmarked", chinese: "未标记")
    }

    static func releaseName(_ identifier: String, language: AppLanguage) -> String {
        switch identifier {
        case "language-settings", "Language preference and rebrand":
            return choose(
                language,
                english: "Governor rename and language settings",
                chinese: "Governor 改名与语言设置"
            )
        case "Settings accessibility":
            return choose(
                language,
                english: "Settings accessibility",
                chinese: "设置可访问性改进"
            )
        default:
            return identifier
        }
    }

    static func versionLine(
        version: String,
        releaseName: String,
        language: AppLanguage
    ) -> String {
        "\(productName) \(version) · \(releaseName)"
    }
}

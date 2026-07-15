import GovernorCore

extension PowerMode {
    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .lowPower:
            AppText.choose(language, english: "Low Power", chinese: "低电量")
        case .automatic:
            AppText.choose(language, english: "Automatic", chinese: "自动")
        case .highPower:
            AppText.choose(language, english: "High Power", chinese: "高性能")
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .lowPower:
            "leaf.fill"
        case .automatic:
            "bolt.circle"
        case .highPower:
            "bolt.fill"
        }
    }
}

extension AutomationStatus {
    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .disabled:
            AppText.choose(language, english: "Disabled", chinese: "已关闭")
        case .starting:
            AppText.choose(language, english: "Starting", chinese: "正在启动")
        case .running:
            AppText.choose(language, english: "Running", chinese: "运行中")
        case .pausedForManualChange:
            AppText.choose(language, english: "Paused", chinese: "已暂停")
        case .restoring:
            AppText.choose(language, english: "Restoring", chinese: "正在恢复")
        case let .errorStopped(failure):
            AppText.choose(
                language,
                english: "Stopped: \(failure.displayText(in: language))",
                chinese: "已停止：\(failure.displayText(in: language))"
            )
        }
    }

    var isPaused: Bool {
        self == .pausedForManualChange
    }
}

extension AutomationFailure {
    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .permissionDenied:
            AppText.choose(language, english: "Permission denied", chinese: "权限不足")
        case .systemReadFailed:
            AppText.choose(language, english: "Read failed", chinese: "读取失败")
        case .invalidDecisionInput:
            AppText.choose(language, english: "Invalid state", chinese: "状态无效")
        case .switchRequestFailed:
            AppText.choose(language, english: "Switch failed", chinese: "切换失败")
        case .confirmationReadFailed:
            AppText.choose(language, english: "Confirmation read failed", chinese: "确认失败")
        case .confirmationMismatch:
            AppText.choose(language, english: "Switch did not take effect", chinese: "切换未生效")
        case .historyReadFailed:
            AppText.choose(language, english: "History read failed", chinese: "记录读取失败")
        case .historyWriteFailed:
            AppText.choose(language, english: "History save failed", chinese: "记录保存失败")
        case .highPowerUnavailableForRestoration:
            AppText.choose(language, english: "Unable to restore the previous mode", chinese: "无法恢复原模式")
        }
    }
}

extension DecisionReason {
    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .highPowerBecameUnavailable:
            AppText.choose(language, english: "High Power is no longer available", chinese: "High Power 不再可用")
        case .idleThresholdReached:
            AppText.choose(language, english: "Using the idle power mode", chinese: "已使用空闲电源模式")
        case .userActive:
            AppText.choose(language, english: "Using the active power mode", chinese: "已使用活跃电源模式")
        }
    }
}

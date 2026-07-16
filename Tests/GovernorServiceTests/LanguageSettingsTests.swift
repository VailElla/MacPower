import Foundation
import Testing
@testable import Governor

@Suite("Language settings")
@MainActor
struct LanguageSettingsTests {
    @Test
    func systemDefaultUsesEnglishUnlessThePrimaryLanguageIsChinese() {
        #expect(AppLanguage.defaultLanguage(preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguage.defaultLanguage(preferredLanguages: ["ja-JP"]) == .english)
        #expect(AppLanguage.defaultLanguage(preferredLanguages: ["zh-Hans"]) == .chinese)
        #expect(AppLanguage.defaultLanguage(preferredLanguages: ["zh-Hant-TW"]) == .chinese)
        #expect(AppLanguage.defaultLanguage(preferredLanguages: []) == .english)
    }

    @Test
    func savedChoiceOverridesTheSystemDefaultAndPersists() {
        let suiteName = "Governor.LanguageSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = LanguageSettings(
            defaults: defaults,
            preferredLanguages: ["zh-Hans"]
        )
        #expect(settings.language == .chinese)

        settings.select(.english)
        #expect(defaults.string(forKey: "Governor.settings.language") == "english")

        let reloaded = LanguageSettings(
            defaults: defaults,
            preferredLanguages: ["zh-Hans"]
        )
        #expect(reloaded.language == .english)
    }

    @Test
    func selectingTheAlreadyVisibleLanguageStillSavesAnExplicitPreference() {
        let suiteName = "Governor.LanguageSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = LanguageSettings(
            defaults: defaults,
            preferredLanguages: ["zh-Hans"]
        )
        settings.select(.chinese)

        #expect(defaults.string(forKey: "Governor.settings.language") == "chinese")
    }

    @Test
    func languageSpecificStringsCoverTheSettingsWindowTitle() {
        #expect(AppText.automationSettingsTitle(.english) == "Automation")
        #expect(AppText.automationSettingsTitle(.chinese) == "自动切换")
        #expect(AppText.language(.english) == "Language")
        #expect(AppText.language(.chinese) == "语言")
        #expect(
            AppText.releaseName("Language preference and rebrand", language: .chinese)
                == "Governor 改名与语言设置"
        )
        #expect(
            AppText.releaseName("Settings accessibility", language: .chinese)
                == "设置可访问性改进"
        )
    }
}

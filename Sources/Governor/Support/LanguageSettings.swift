import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Sendable, Hashable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var selectionTitle: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "中文"
        }
    }

    static func defaultLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        guard let primaryLanguage = preferredLanguages.first?.lowercased() else {
            return .english
        }

        return primaryLanguage == "zh"
            || primaryLanguage.hasPrefix("zh-")
            || primaryLanguage.hasPrefix("zh_")
            ? .chinese
            : .english
    }
}

/// Keeps an explicit user choice separate from the first-launch system default.
/// When no choice has been saved, the primary system language is evaluated on
/// launch: Chinese defaults to Chinese and every other language defaults to English.
@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    private enum Key {
        static let language = "Governor.settings.language"
    }

    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        language = defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.defaultLanguage(preferredLanguages: preferredLanguages)
    }

    func select(_ language: AppLanguage) {
        if self.language != language {
            self.language = language
        }
        defaults.set(language.rawValue, forKey: Key.language)
    }
}

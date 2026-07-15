import Foundation

enum AppVersion {
    static var version: String {
        bundleValue(forKey: "CFBundleShortVersionString") ?? ""
    }

    static var rawReleaseName: String {
        bundleValue(forKey: "GovernorReleaseName") ?? ""
    }

    static func releaseName(in language: AppLanguage) -> String {
        guard !rawReleaseName.isEmpty else {
            return AppText.unmarkedRelease(language)
        }
        return AppText.releaseName(rawReleaseName, language: language)
    }

    static func displayText(in language: AppLanguage) -> String {
        let displayVersion = version.isEmpty
            ? AppText.developmentBuild(language)
            : version
        return AppText.versionLine(
            version: displayVersion,
            releaseName: releaseName(in: language),
            language: language
        )
    }

    private static func bundleValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

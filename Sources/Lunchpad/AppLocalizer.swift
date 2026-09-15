import Foundation

private enum AppResourceBundle {
    static let name = "Lunchpad_Lunchpad.bundle"

    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourceURL.appendingPathComponent(name, isDirectory: true)
           ) {
            return packagedBundle
        }
        return .module
    }()
}

@MainActor
final class AppLocalizer {
    private let resourceBundle: Bundle
    private let preferredLanguages: () -> [String]
    private(set) var selectedLanguage: InterfaceLanguage
    var onChange: (() -> Void)?

    init(
        language: InterfaceLanguage,
        resourceBundle: Bundle? = nil,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        selectedLanguage = language
        self.resourceBundle = resourceBundle ?? AppResourceBundle.bundle
        self.preferredLanguages = preferredLanguages
    }

    var resolvedLanguage: ResolvedLanguage {
        selectedLanguage.resolved(preferredLanguages: preferredLanguages())
    }

    func setLanguage(_ language: InterfaceLanguage) {
        guard selectedLanguage != language else { return }
        selectedLanguage = language
        onChange?()
    }

    func string(_ key: String) -> String {
        let english = localizedString(key, language: .english)
        let selected = localizedString(key, language: resolvedLanguage)
        if selected != key { return selected }
        if english != key { return english }
        return key
    }

    func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: resolvedLanguage.locale,
            arguments: arguments
        )
    }

    private func localizedString(_ key: String, language: ResolvedLanguage) -> String {
        let resourceName = language.rawValue.lowercased()
        // A localization directory is not an ordinary resource: on macOS 27,
        // path(forResource:ofType:) may resolve it through the process's preferred localization
        // and return the English directory even when zh-Hans was requested explicitly.
        guard let resourceURL = resourceBundle.resourceURL else { return key }
        // SwiftPM toolchains use either zh-hans.lproj or zh-Hans.lproj. Try both exact names
        // so explicit language selection also works on case-sensitive volumes.
        let directoryNames = [resourceName, language.rawValue]
        guard let languageBundle = directoryNames.lazy.compactMap({ name in
            Bundle(url: resourceURL.appendingPathComponent("\(name).lproj", isDirectory: true))
        }).first else {
            return key
        }
        return languageBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

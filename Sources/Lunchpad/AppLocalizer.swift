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
        guard let path = resourceBundle.path(forResource: resourceName, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else {
            return key
        }
        return languageBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

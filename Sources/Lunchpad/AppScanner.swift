import Foundation

/// A discovered application. Its identifier preserves layout identity independently of path.
struct AppItem {
    let identifier: String
    let bundleIdentifier: String?
    let name: String
    let url: URL
}

/// A logical Lunchpad folder with no relationship to a Finder directory.
struct AppFolder {
    let identifier: String
    let name: String
    let apps: [AppItem]
    let isSystem: Bool
}

/// The root page can contain individual applications and logical folders.
enum LunchpadItem {
    case app(AppItem)
    case folder(AppFolder)

    var name: String {
        switch self {
        case .app(let app): app.name
        case .folder(let folder): folder.name
        }
    }

    var apps: [AppItem] {
        switch self {
        case .app(let app): [app]
        case .folder(let folder): folder.apps
        }
    }
}

/// A discovery result that has not yet been reconciled into the layout database.
struct DiscoveredApplication {
    let item: AppItem
    let shouldDefaultToOther: Bool
}

/// Describes on-disk state for detecting an incomplete app copy; not part of app identity.
struct ApplicationBundleFingerprint: Equatable {
    let appPath: String
    let appModificationDate: TimeInterval?
    let infoPlistModificationDate: TimeInterval?
    let infoPlistSize: UInt64?
    let executablePath: String?
    let executableModificationDate: TimeInterval?
    let executableSize: UInt64?
}

/// Scans common Applications roots. Finder hierarchy is used for discovery, not grouping.
final class AppScanner {
    private let roots: [URL]
    private let utilityRoots: [URL]

    var monitoredRoots: [URL] { roots }

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        utilityRoots = [
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]
    }

    func scanApplications(using store: LunchpadLayoutStore) throws -> [LunchpadItem] {
        try store.reconcile(discoverApplications())
    }

    /// Safe fallback when the database is unavailable: show all apps without inferred folders.
    func scanApplicationsFlat() -> [LunchpadItem] {
        discoverApplications().map { .app($0.item) }
    }

    /// Disk state is stable enough to persist only when two snapshots are identical.
    func captureStabilitySnapshot() -> [ApplicationBundleFingerprint] {
        applicationBundleURLs().map(makeFingerprint).sorted {
            $0.appPath.localizedStandardCompare($1.appPath) == .orderedAscending
        }
    }

    func discoverApplications() -> [DiscoveredApplication] {
        var discovered: [DiscoveredApplication] = []
        var seenIdentifiers = Set<String>()

        for url in applicationBundleURLs() {
            guard let app = makeApp(at: url),
                      seenIdentifiers.insert(app.identifier).inserted else {
                continue
            }

            discovered.append(DiscoveredApplication(
                item: app,
                shouldDefaultToOther: isInsideUtilities(app.url)
            ))
        }

        return discovered.sorted {
            $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending
        }
    }

    private func makeApp(at url: URL) -> AppItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        let infoPlist = canonicalURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlist) as? [String: Any],
              let executableName = nonEmptyString(info["CFBundleExecutable"]),
              FileManager.default.fileExists(
                  atPath: canonicalURL
                      .appendingPathComponent("Contents/MacOS", isDirectory: true)
                      .appendingPathComponent(executableName)
                      .path
              ) else {
            // Finder creates the package directory before a copy finishes. Do not expose an
            // app until both its plist and main executable are complete.
            return nil
        }
        let bundleIdentifier = (info["CFBundleIdentifier"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        let displayName = localizedDisplayName(
            for: canonicalURL,
            rawInfoDictionary: info
        )

        let identifier = bundleIdentifier.map { "bundle:\($0.lowercased())" }
            ?? "path:\(canonicalURL.path)"
        return AppItem(
            identifier: identifier,
            bundleIdentifier: bundleIdentifier,
            name: displayName,
            url: canonicalURL
        )
    }

    private func localizedDisplayName(
        for appURL: URL,
        rawInfoDictionary: [String: Any]?
    ) -> String {
        if let bundle = Bundle(url: appURL),
           let localizedName = localizedInfoPlistName(in: bundle) {
            return localizedName
        }

        // Some apps declare localized display names only through filesystem resources.
        if let localizedFileName = try? appURL.resourceValues(
            forKeys: [.localizedNameKey]
        ).localizedName,
           !localizedFileName.isEmpty {
            return URL(fileURLWithPath: localizedFileName)
                .deletingPathExtension()
                .lastPathComponent
        }

        return nonEmptyString(rawInfoDictionary?["CFBundleDisplayName"])
            ?? nonEmptyString(rawInfoDictionary?["CFBundleName"])
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    /// Tahoe system apps mainly use InfoPlist.loctable; third-party apps usually retain
    /// localized *.lproj/InfoPlist.strings files.
    private func localizedInfoPlistName(in bundle: Bundle) -> String? {
        let preferredLocalizations = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: Locale.preferredLanguages
        )

        if let tableURL = bundle.url(
            forResource: "InfoPlist",
            withExtension: "loctable"
        ),
           let table = propertyListDictionary(at: tableURL) {
            for localization in preferredLocalizations {
                guard let localizedValues = table[localization] as? [String: Any] else {
                    continue
                }
                if let name = infoPlistName(in: localizedValues) {
                    return name
                }
            }
        }

        for localization in preferredLocalizations {
            guard let stringsURL = bundle.url(
                forResource: "InfoPlist",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ),
            let strings = propertyListDictionary(at: stringsURL),
            let name = infoPlistName(in: strings) else {
                continue
            }
            return name
        }

        // Bundle resolves the current language for ordinary app bundles; keep it as the
        // final localization fallback.
        return nonEmptyString(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName"))
            ?? nonEmptyString(bundle.object(forInfoDictionaryKey: "CFBundleName"))
    }

    private func propertyListDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) else {
            return nil
        }
        return propertyList as? [String: Any]
    }

    private func infoPlistName(in dictionary: [String: Any]) -> String? {
        nonEmptyString(dictionary["CFBundleDisplayName"])
            ?? nonEmptyString(dictionary["CFBundleName"])
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func isInsideUtilities(_ appURL: URL) -> Bool {
        let path = appURL.resolvingSymlinksInPath().standardizedFileURL.path
        return utilityRoots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(rootPath + "/")
        }
    }

    private func applicationBundleURLs() -> [URL] {
        var urls: [URL] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                // Always skip package contents. The snapshot records the key files required
                // to determine bundle completeness.
                enumerator.skipDescendants()
                urls.append(url.resolvingSymlinksInPath().standardizedFileURL)
            }
        }
        return urls
    }

    private func makeFingerprint(at appURL: URL) -> ApplicationBundleFingerprint {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
        let executableURL = nonEmptyString(info?["CFBundleExecutable"]).map {
            appURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent($0)
        }
        let appState = fileState(at: appURL)
        let infoState = fileState(at: infoPlistURL)
        let executableState = executableURL.flatMap(fileState)

        return ApplicationBundleFingerprint(
            appPath: appURL.path,
            appModificationDate: appState?.modificationDate,
            infoPlistModificationDate: infoState?.modificationDate,
            infoPlistSize: infoState?.size,
            executablePath: executableURL?.path,
            executableModificationDate: executableState?.modificationDate,
            executableSize: executableState?.size
        )
    }

    private func fileState(at url: URL) -> (modificationDate: TimeInterval, size: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let date = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return (date, size)
    }
}

import Foundation

enum ApplicationOrderingPolicy {
    static func apply(
        to items: [LunchpadItem],
        order: ApplicationSortOrder,
        locale: Locale,
        otherFolderName: String
    ) -> [LunchpadItem] {
        let preparedItems = items.map { item -> LunchpadItem in
            guard case .folder(let folder) = item else { return item }
            return .folder(AppFolder(
                identifier: folder.identifier,
                name: folder.identifier == LunchpadLayoutStore.otherFolderIdentifier
                    ? otherFolderName
                    : folder.name,
                apps: sorted(folder.apps, order: order, locale: locale),
                isSystem: folder.isSystem
            ))
        }

        var rootApps = sorted(
            preparedItems.compactMap { item -> AppItem? in
                guard case .app(let app) = item else { return nil }
                return app
            },
            order: order,
            locale: locale
        ).makeIterator()

        return preparedItems.map { item in
            guard case .app = item, let app = rootApps.next() else { return item }
            return .app(app)
        }
    }

    static func sorted(
        _ apps: [AppItem],
        order: ApplicationSortOrder,
        locale: Locale
    ) -> [AppItem] {
        apps.sorted { lhs, rhs in
            let dates: (left: Date?, right: Date?)?
            switch order {
            case .name:
                dates = nil
            case .creationDate:
                dates = (lhs.creationDate, rhs.creationDate)
            case .modificationDate:
                dates = (lhs.modificationDate, rhs.modificationDate)
            }

            if let dates {
                switch (dates.left, dates.right) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
            }

            let nameOrder = lhs.name.compare(
                rhs.name,
                options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                range: nil,
                locale: locale
            )
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.identifier < rhs.identifier
        }
    }
}

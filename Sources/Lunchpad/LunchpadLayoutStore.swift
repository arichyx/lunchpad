import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum LunchpadLayoutStoreError: Error, CustomStringConvertible {
    case sqlite(String)
    case invalidFolderName
    case folderNotFound
    case applicationNotFound
    case protectedSystemFolder
    case unsupportedSchemaVersion(Int64)

    var description: String {
        switch self {
        case .sqlite(let message): message
        case .unsupportedSchemaVersion(let version):
            "Layout database schema version \(version) is newer than this build supports"
        case .invalidFolderName: "Folder name must not be empty"
        case .folderNotFound: "Folder not found"
        case .applicationNotFound: "Application not found"
        case .protectedSystemFolder: "System folders cannot be deleted or renamed"
        }
    }
}

/// Lunchpad's layout database. Finder paths locate apps; this store owns folder assignments.
final class LunchpadLayoutStore: @unchecked Sendable {
    static let otherFolderIdentifier = "system.other"
    /// The newest schema this build can read and write. Raise it together with a new step in
    /// `migrate()`.
    static let currentSchemaVersion: Int64 = 1
    private static let defaultOtherSortPosition: Int64 = 9_000_000_000

    private enum AssignmentSource: String {
        case none
        case `default`
        case user
    }

    private enum Value {
        case text(String)
        case int64(Int64)
        case double(Double)
        case null
    }

    private struct ExistingAssignment {
        let folderIdentifier: String?
        let source: AssignmentSource
    }

    private struct StoredApplication {
        let bundleIdentifier: String?
        let displayName: String
        let path: String
        let folderIdentifier: String?
        let source: AssignmentSource
        let isPresent: Bool

        func needsUpdate(for app: AppItem) -> Bool {
            !isPresent
                || bundleIdentifier != app.bundleIdentifier
                || displayName != app.name
                || path != app.url.path
        }
    }

    private struct PositionedItem {
        let position: Int64
        let name: String
        let item: LunchpadItem
    }

    private struct PositionedRootSlot {
        let position: Int64
        let name: String
        let slot: LunchpadRootSlot
    }

    private let accessLock = NSRecursiveLock()
    private var database: OpaquePointer?
    let databaseURL: URL

    init(databaseURL: URL? = nil) throws {
        self.databaseURL = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let result = sqlite3_open_v2(
            self.databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unable to open layout database"
            if let database { sqlite3_close(database) }
            database = nil
            throw LunchpadLayoutStoreError.sqlite(message)
        }

        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA busy_timeout = 2000")
            try migrate()
            try seedSystemFolders()
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    /// Reconciles discovered applications and loads the root and logical-folder layout.
    ///
    /// Only rows whose metadata or presence changed are written, so a refresh that finds the same
    /// applications leaves the database untouched. `last_seen_at` therefore records when an
    /// application last appeared or changed, not every scan that observed it.
    func reconcile(_ discoveredApplications: [DiscoveredApplication]) throws -> [LunchpadItem] {
        try withAccessLock {
            try transaction {
                // Root applications and visible folders share one position namespace. Calculate
                // the append position while the preceding snapshot is still marked present.
                var nextRootPosition = try nextRootItemPosition()
                var nextOtherPosition = try nextApplicationPosition(
                    folderIdentifier: Self.otherFolderIdentifier
                )
                let storedApplications = try loadStoredApplications()
                var discoveredIdentifiers = Set<String>()
                let now = Date().timeIntervalSince1970

                for discovered in discoveredApplications {
                    let app = discovered.item
                    guard discoveredIdentifiers.insert(app.identifier).inserted else { continue }

                    if let existing = storedApplications[app.identifier] {
                        if existing.needsUpdate(for: app) {
                            try execute(
                                """
                                UPDATE applications
                                SET bundle_identifier = ?, display_name = ?, path = ?,
                                    is_present = 1, last_seen_at = ?
                                WHERE id = ?
                                """,
                                [
                                    app.bundleIdentifier.map(Value.text) ?? .null,
                                    .text(app.name),
                                    .text(app.url.path),
                                    .double(now),
                                    .text(app.identifier),
                                ]
                            )
                        }

                        // Only untouched root applications may receive the default Other
                        // assignment.
                        if discovered.shouldDefaultToOther,
                           existing.folderIdentifier == nil,
                           existing.source == .none {
                            try setAssignment(
                                appIdentifier: app.identifier,
                                folderIdentifier: Self.otherFolderIdentifier,
                                position: nextOtherPosition,
                                source: .default
                            )
                            nextOtherPosition += 1
                        }
                        continue
                    }

                    let folderIdentifier = discovered.shouldDefaultToOther
                        ? Self.otherFolderIdentifier
                        : nil
                    let position: Int64
                    let source: AssignmentSource
                    if folderIdentifier == nil {
                        position = nextRootPosition
                        nextRootPosition += 1
                        source = .none
                    } else {
                        position = nextOtherPosition
                        nextOtherPosition += 1
                        source = .default
                    }

                    try execute(
                        """
                        INSERT INTO applications(
                            id, bundle_identifier, display_name, path, folder_id,
                            sort_position, assignment_source, is_present,
                            first_seen_at, last_seen_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                        """,
                        [
                            .text(app.identifier),
                            app.bundleIdentifier.map(Value.text) ?? .null,
                            .text(app.name),
                            .text(app.url.path),
                            folderIdentifier.map(Value.text) ?? .null,
                            .int64(position),
                            .text(source.rawValue),
                            .double(now),
                            .double(now),
                        ]
                    )
                }

                // Applications missing from this snapshot keep their layout for a reinstall.
                for (identifier, stored) in storedApplications
                where stored.isPresent && !discoveredIdentifiers.contains(identifier) {
                    try execute(
                        "UPDATE applications SET is_present = 0 WHERE id = ?",
                        [.text(identifier)]
                    )
                }
            }

            return try loadVisibleItems()
        }
    }

    private func loadStoredApplications() throws -> [String: StoredApplication] {
        let statement = try prepare(
            """
            SELECT id, bundle_identifier, display_name, path, folder_id,
                   assignment_source, is_present
            FROM applications
            """
        )
        defer { sqlite3_finalize(statement) }

        var applications: [String: StoredApplication] = [:]
        while try step(statement) == SQLITE_ROW {
            applications[textColumn(statement, index: 0)] = StoredApplication(
                bundleIdentifier: optionalTextColumn(statement, index: 1),
                displayName: textColumn(statement, index: 2),
                path: textColumn(statement, index: 3),
                folderIdentifier: optionalTextColumn(statement, index: 4),
                source: AssignmentSource(rawValue: textColumn(statement, index: 5)) ?? .none,
                isPresent: sqlite3_column_int(statement, 6) != 0
            )
        }
        return applications
    }

    /// Total rows changed through this connection since it opened. Tests use it to verify that
    /// unchanged refreshes do not write.
    var totalChangeCount: Int64 {
        withAccessLock {
            database.map { sqlite3_total_changes64($0) } ?? 0
        }
    }

    @discardableResult
    func createFolder(name rawName: String) throws -> String {
        try withAccessLock {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw LunchpadLayoutStoreError.invalidFolderName }

            let identifier = UUID().uuidString.lowercased()
            let position = try nextUserFolderPosition()
            try execute(
                """
                INSERT INTO folders(
                    id, system_key, name, sort_position, created_at, is_system, is_default
                ) VALUES (?, NULL, ?, ?, ?, 0, 0)
                """,
                [
                    .text(identifier),
                    .text(name),
                    .int64(position),
                    .double(Date().timeIntervalSince1970),
                ]
            )
            return identifier
        }
    }

    func renameFolder(identifier: String, name rawName: String) throws {
        try withAccessLock {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw LunchpadLayoutStoreError.invalidFolderName }
            guard let isSystem = try folderSystemFlag(identifier: identifier) else {
                throw LunchpadLayoutStoreError.folderNotFound
            }
            guard !isSystem else { throw LunchpadLayoutStoreError.protectedSystemFolder }

            try execute(
                "UPDATE folders SET name = ? WHERE id = ?",
                [.text(name), .text(identifier)]
            )
        }
    }

    /// Deleting a logical folder removes assignments without touching app bundles on disk. Its
    /// applications take the folder's place in the root order, keeping their folder order.
    func deleteFolder(identifier: String) throws {
        try withAccessLock {
            guard let isSystem = try folderSystemFlag(identifier: identifier) else {
                throw LunchpadLayoutStoreError.folderNotFound
            }
            guard !isSystem else { throw LunchpadLayoutStoreError.protectedSystemFolder }

            try transaction {
                let rootOrder = try positionedRootSlots(
                    excludingApplications: [],
                    excludingFolders: []
                )
                let memberSlots = try applicationIdentifiers(in: identifier).map {
                    LunchpadRootSlot.app(identifier: $0)
                }
                for case .app(let appIdentifier) in memberSlots {
                    try setAssignment(
                        appIdentifier: appIdentifier,
                        folderIdentifier: nil,
                        position: 0,
                        source: .user
                    )
                }
                try execute("DELETE FROM folders WHERE id = ?", [.text(identifier)])

                let folderSlot = LunchpadRootSlot.folder(identifier: identifier)
                var arrangedSlots = rootOrder.flatMap { slot in
                    slot == folderSlot ? memberSlots : [slot]
                }
                if !rootOrder.contains(folderSlot) {
                    arrangedSlots.append(contentsOf: memberSlots)
                }
                try writeRootOrder(arrangedSlots)
            }
        }
    }

    /// Assigns consecutive root positions in the given order.
    private func writeRootOrder(_ slots: [LunchpadRootSlot]) throws {
        for (index, slot) in slots.enumerated() {
            switch slot {
            case .app(let identifier):
                try execute(
                    "UPDATE applications SET sort_position = ? WHERE id = ? AND folder_id IS NULL",
                    [.int64(Int64(index)), .text(identifier)]
                )
            case .folder(let identifier):
                try execute(
                    "UPDATE folders SET sort_position = ? WHERE id = ?",
                    [.int64(Int64(index)), .text(identifier)]
                )
            }
        }
    }

    /// Persists a completed drag interaction. Each outcome runs in one transaction so a stale
    /// or invalid arrangement leaves the stored layout untouched.
    func commit(_ drag: LunchpadDragCommit) throws {
        try withAccessLock {
            switch drag {
            case .rootRearranged(let slots):
                try transaction {
                    try applyRootSlots(slots, skippingMissingFolders: false)
                }

            case .folderRearranged(let folderIdentifier, let appIdentifiers, let rootSlots):
                try transaction {
                    guard try folderSystemFlag(identifier: folderIdentifier) != nil else {
                        throw LunchpadLayoutStoreError.folderNotFound
                    }
                    try applyFolderOrder(
                        folderIdentifier: folderIdentifier,
                        appIdentifiers: appIdentifiers
                    )
                    try applyRootSlots(rootSlots, skippingMissingFolders: false)
                }

            case .folderCreated(
                let name,
                let appIdentifiers,
                let insertionIndex,
                let remainingSlots
            ):
                try transaction {
                    guard appIdentifiers.count == 2,
                          Set(appIdentifiers).count == appIdentifiers.count else {
                        throw LunchpadLayoutStoreError.applicationNotFound
                    }
                    for appIdentifier in appIdentifiers {
                        guard try presentApplicationExists(
                            identifier: appIdentifier,
                            folderIdentifier: nil
                        ) else {
                            throw LunchpadLayoutStoreError.applicationNotFound
                        }
                    }
                    let folderIdentifier = try createFolder(name: name)
                    for (index, appIdentifier) in appIdentifiers.enumerated() {
                        try setAssignment(
                            appIdentifier: appIdentifier,
                            folderIdentifier: folderIdentifier,
                            position: Int64(index),
                            source: .user
                        )
                    }
                    try applyRootSlots(
                        remainingSlots,
                        skippingMissingFolders: false,
                        folderSlotPlaceholder: (identifier: folderIdentifier, index: insertionIndex)
                    )
                }

            case .appAddedToFolder(let appIdentifier, let folderIdentifier, let rootSlots):
                try transaction {
                    guard try presentApplicationExists(
                        identifier: appIdentifier,
                        folderIdentifier: nil
                    ) else {
                        throw LunchpadLayoutStoreError.applicationNotFound
                    }
                    try assignApplication(identifier: appIdentifier, toFolder: folderIdentifier)
                    try applyRootSlots(rootSlots, skippingMissingFolders: false)
                }

            case .appRemovedToRoot(let appIdentifier, let sourceFolderIdentifier, let slots):
                try transaction {
                    guard try presentApplicationExists(
                        identifier: appIdentifier,
                        folderIdentifier: sourceFolderIdentifier
                    ) else {
                        throw LunchpadLayoutStoreError.applicationNotFound
                    }
                    // The supplied root arrangement fixes the final position.
                    try setAssignment(
                        appIdentifier: appIdentifier,
                        folderIdentifier: nil,
                        position: 0,
                        source: .user
                    )
                    try deleteFolderIfEmptyUserFolder(sourceFolderIdentifier)
                    try applyRootSlots(slots, skippingMissingFolders: true)
                }
            }
        }
    }

    /// Writes root-level positions for the supplied slots and appends any unlisted root items
    /// after them in their existing relative order. `folderSlotPlaceholder` positions a newly
    /// created folder inside the arrangement; it carries no slot itself.
    private func applyRootSlots(
        _ slots: [LunchpadRootSlot],
        skippingMissingFolders: Bool,
        folderSlotPlaceholder: (identifier: String, index: Int)? = nil
    ) throws {
        let listedAppIdentifiers = slots.compactMap { slot -> String? in
            guard case .app(let identifier) = slot else { return nil }
            return identifier
        }
        let listedFolderIdentifiers = slots.compactMap { slot -> String? in
            guard case .folder(let identifier) = slot else { return nil }
            return identifier
        }

        // When a placeholder folder is inserted at an index, listed slots at or after that
        // index shift one position right to make room for it.
        func position(for index: Int) -> Int64 {
            guard let placeholder = folderSlotPlaceholder, index >= placeholder.index else {
                return Int64(index)
            }
            return Int64(index + 1)
        }

        for (index, slot) in slots.enumerated() {
            switch slot {
            case .app(let identifier):
                guard try presentApplicationExists(identifier: identifier, folderIdentifier: nil) else {
                    throw LunchpadLayoutStoreError.applicationNotFound
                }
                try execute(
                    "UPDATE applications SET sort_position = ? WHERE id = ? AND folder_id IS NULL",
                    [.int64(position(for: index)), .text(identifier)]
                )
            case .folder(let identifier):
                guard try folderSystemFlag(identifier: identifier) != nil else {
                    guard skippingMissingFolders else {
                        throw LunchpadLayoutStoreError.folderNotFound
                    }
                    continue
                }
                try execute(
                    "UPDATE folders SET sort_position = ? WHERE id = ?",
                    [.int64(position(for: index)), .text(identifier)]
                )
            }
        }

        if let placeholder = folderSlotPlaceholder {
            try execute(
                "UPDATE folders SET sort_position = ? WHERE id = ?",
                [.int64(Int64(placeholder.index)), .text(placeholder.identifier)]
            )
        }

        // Root items the caller did not list keep their mixed application/folder order after the
        // listed ones. The newly created folder is positioned by its placeholder, never as an
        // unlisted item.
        let nextPosition = Int64(slots.count + (folderSlotPlaceholder != nil ? 1 : 0))
        var unlistedFolderExclusions = listedFolderIdentifiers
        if let placeholder = folderSlotPlaceholder {
            unlistedFolderExclusions.append(placeholder.identifier)
        }
        let unlistedSlots = try positionedRootSlots(
            excludingApplications: listedAppIdentifiers,
            excludingFolders: unlistedFolderExclusions
        )
        for (offset, slot) in unlistedSlots.enumerated() {
            let position = nextPosition + Int64(offset)
            switch slot {
            case .app(let identifier):
                try execute(
                    "UPDATE applications SET sort_position = ? WHERE id = ?",
                    [.int64(position), .text(identifier)]
                )
            case .folder(let identifier):
                try execute(
                    "UPDATE folders SET sort_position = ? WHERE id = ?",
                    [.int64(position), .text(identifier)]
                )
            }
        }
    }

    private func positionedRootSlots(
        excludingApplications appIdentifiers: [String],
        excludingFolders folderIdentifiers: [String]
    ) throws -> [LunchpadRootSlot] {
        var positionedSlots: [PositionedRootSlot] = []

        let appStatement = try prepare(
            """
            SELECT id, sort_position, display_name
            FROM applications WHERE folder_id IS NULL
            """ + notInClause(for: appIdentifiers)
        )
        defer { sqlite3_finalize(appStatement) }
        try bind(appIdentifiers.map(Value.text), to: appStatement)
        while try step(appStatement) == SQLITE_ROW {
            positionedSlots.append(PositionedRootSlot(
                position: sqlite3_column_int64(appStatement, 1),
                name: textColumn(appStatement, index: 2),
                slot: .app(identifier: textColumn(appStatement, index: 0))
            ))
        }

        let folderStatement = try prepare(
            """
            SELECT id, sort_position, name FROM folders
            WHERE NOT (is_default = 1 AND sort_position = \(Self.defaultOtherSortPosition))
            """ + notInClause(for: folderIdentifiers)
        )
        defer { sqlite3_finalize(folderStatement) }
        try bind(folderIdentifiers.map(Value.text), to: folderStatement)
        while try step(folderStatement) == SQLITE_ROW {
            positionedSlots.append(PositionedRootSlot(
                position: sqlite3_column_int64(folderStatement, 1),
                name: textColumn(folderStatement, index: 2),
                slot: .folder(identifier: textColumn(folderStatement, index: 0))
            ))
        }

        return positionedSlots.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return rootSlotSortKey($0.slot) < rootSlotSortKey($1.slot)
        }.map(\.slot)
    }

    private func rootSlotSortKey(_ slot: LunchpadRootSlot) -> String {
        switch slot {
        case .app(let identifier): "app:\(identifier)"
        case .folder(let identifier): "folder:\(identifier)"
        }
    }

    /// Writes member positions for one folder and appends any unlisted members after them.
    private func applyFolderOrder(
        folderIdentifier: String,
        appIdentifiers: [String]
    ) throws {
        for (index, appIdentifier) in appIdentifiers.enumerated() {
            guard try presentApplicationExists(
                identifier: appIdentifier,
                folderIdentifier: folderIdentifier
            ) else {
                throw LunchpadLayoutStoreError.applicationNotFound
            }
            try execute(
                """
                UPDATE applications SET sort_position = ?
                WHERE id = ? AND folder_id = ?
                """,
                [.int64(Int64(index)), .text(appIdentifier), .text(folderIdentifier)]
            )
        }

        let unlisted = try applicationIdentifiers(
            matching: """
            SELECT id FROM applications WHERE folder_id = ?
            """ + notInClause(for: appIdentifiers) + " ORDER BY sort_position",
            excluding: appIdentifiers,
            bindingFolderIdentifier: folderIdentifier
        )
        for (offset, identifier) in unlisted.enumerated() {
            try execute(
                "UPDATE applications SET sort_position = ? WHERE id = ?",
                [.int64(Int64(appIdentifiers.count + offset)), .text(identifier)]
            )
        }
    }

    private func deleteFolderIfEmptyUserFolder(_ folderIdentifier: String) throws {
        guard let isSystem = try folderSystemFlag(identifier: folderIdentifier) else { return }
        guard !isSystem else { return }
        let memberCount = try scalarInt64(
            "SELECT COUNT(*) FROM applications WHERE folder_id = ?",
            values: [.text(folderIdentifier)]
        )
        guard memberCount == 0 else { return }
        try execute("DELETE FROM folders WHERE id = ?", [.text(folderIdentifier)])
    }

    /// `NOT IN (...)` needs a dynamic placeholder list; an empty exclusion list drops the clause.
    private func notInClause(for identifiers: [String], conjunction: String = " AND ") -> String {
        guard !identifiers.isEmpty else { return "" }
        return conjunction + "id NOT IN ("
            + identifiers.map { _ in "?" }.joined(separator: ", ")
            + ")"
    }

    private func applicationIdentifiers(
        matching sql: String,
        excluding: [String],
        bindingFolderIdentifier: String? = nil
    ) throws -> [String] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var values: [Value] = bindingFolderIdentifier.map { [Value.text($0)] } ?? []
        values.append(contentsOf: excluding.map(Value.text))
        try bind(values, to: statement)

        var identifiers: [String] = []
        while try step(statement) == SQLITE_ROW {
            identifiers.append(textColumn(statement, index: 0))
        }
        return identifiers
    }

    /// A nil folderIdentifier moves the app to the root. User assignments prevent future
    /// scans from restoring a default folder.
    func assignApplication(
        identifier appIdentifier: String,
        toFolder folderIdentifier: String?
    ) throws {
        try withAccessLock {
            guard try existingAssignment(for: appIdentifier) != nil else {
                throw LunchpadLayoutStoreError.applicationNotFound
            }
            if let folderIdentifier,
               try folderSystemFlag(identifier: folderIdentifier) == nil {
                throw LunchpadLayoutStoreError.folderNotFound
            }

            let position = if folderIdentifier == nil {
                try nextRootItemPosition()
            } else {
                try nextApplicationPosition(folderIdentifier: folderIdentifier)
            }
            try setAssignment(
                appIdentifier: appIdentifier,
                folderIdentifier: folderIdentifier,
                position: position,
                source: .user
            )
        }
    }

    private static func defaultDatabaseURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["LUNCHPAD_DATABASE_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LunchpadLayoutStoreError.sqlite("Application Support directory not found")
        }
        return applicationSupport
            .appendingPathComponent("com.arichyx.Lunchpad", isDirectory: true)
            .appendingPathComponent("layout.sqlite3", isDirectory: false)
    }

    /// Upgrades the schema one version at a time, each step in its own transaction, and records
    /// the result in `PRAGMA user_version`. A database written by a newer build is refused rather
    /// than modified, so the app falls back to the flat layout and the newer data stays intact.
    private func migrate() throws {
        let version = try scalarInt64("PRAGMA user_version", values: [])
        guard version <= Self.currentSchemaVersion else {
            throw LunchpadLayoutStoreError.unsupportedSchemaVersion(version)
        }

        if version < 1 {
            try transaction {
                // Version 1 is the original schema. Earlier builds always stored version 1, so
                // IF NOT EXISTS only matters for an interrupted first launch.
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS folders(
                        id TEXT PRIMARY KEY,
                        system_key TEXT UNIQUE,
                        name TEXT NOT NULL,
                        sort_position INTEGER NOT NULL,
                        created_at REAL NOT NULL,
                        is_system INTEGER NOT NULL DEFAULT 0,
                        is_default INTEGER NOT NULL DEFAULT 0
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS applications(
                        id TEXT PRIMARY KEY,
                        bundle_identifier TEXT,
                        display_name TEXT NOT NULL,
                        path TEXT NOT NULL,
                        folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
                        sort_position INTEGER NOT NULL,
                        assignment_source TEXT NOT NULL DEFAULT 'none'
                            CHECK(assignment_source IN ('none', 'default', 'user')),
                        is_present INTEGER NOT NULL DEFAULT 1,
                        first_seen_at REAL NOT NULL,
                        last_seen_at REAL NOT NULL
                    )
                    """
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS applications_folder_position "
                        + "ON applications(folder_id, sort_position)"
                )
                try execute("PRAGMA user_version = 1")
            }
        }
    }

    private func seedSystemFolders() throws {
        try execute(
            """
            INSERT OR IGNORE INTO folders(
                id, system_key, name, sort_position, created_at, is_system, is_default
            ) VALUES (?, 'other', 'Other', 9000000000, ?, 1, 1)
            """,
            [
                .text(Self.otherFolderIdentifier),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    /// Reloads the stored arrangement: root applications and folders ordered by sort position,
    /// with each folder's present members ordered within it. Called after drag commits so the
    /// presented catalog reflects exactly what was persisted.
    func loadVisibleItems() throws -> [LunchpadItem] {
        try withAccessLock {
            var positionedItems: [PositionedItem] = []

            let rootStatement = try prepare(
                """
                SELECT id, bundle_identifier, display_name, path, sort_position
                FROM applications
                WHERE is_present = 1 AND folder_id IS NULL
                ORDER BY sort_position, display_name COLLATE NOCASE
                """
            )
            defer { sqlite3_finalize(rootStatement) }
            while try step(rootStatement) == SQLITE_ROW {
                let app = appItem(from: rootStatement)
                positionedItems.append(PositionedItem(
                    position: sqlite3_column_int64(rootStatement, 4),
                    name: app.name,
                    item: .app(app)
                ))
            }

            let folderStatement = try prepare(
                """
                SELECT id, name, sort_position, is_system
                FROM folders
                ORDER BY sort_position, name COLLATE NOCASE
                """
            )
            defer { sqlite3_finalize(folderStatement) }
            while try step(folderStatement) == SQLITE_ROW {
                let identifier = textColumn(folderStatement, index: 0)
                let storedName = textColumn(folderStatement, index: 1)
                let apps = try applications(in: identifier, onlyPresent: true)
                guard !apps.isEmpty else { continue }

                let displayedName = storedName
                positionedItems.append(PositionedItem(
                    position: sqlite3_column_int64(folderStatement, 2),
                    name: displayedName,
                    item: .folder(AppFolder(
                        identifier: identifier,
                        name: displayedName,
                        apps: apps,
                        isSystem: sqlite3_column_int(folderStatement, 3) != 0
                    ))
                ))
            }

            return positionedItems.sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }.map(\.item)
        }
    }

    private func applications(in folderIdentifier: String, onlyPresent: Bool) throws -> [AppItem] {
        let sql = """
        SELECT id, bundle_identifier, display_name, path, sort_position
        FROM applications
        WHERE folder_id = ? \(onlyPresent ? "AND is_present = 1" : "")
        ORDER BY sort_position, display_name COLLATE NOCASE
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind([.text(folderIdentifier)], to: statement)

        var apps: [AppItem] = []
        while try step(statement) == SQLITE_ROW {
            apps.append(appItem(from: statement))
        }
        return apps
    }

    private func appItem(from statement: OpaquePointer) -> AppItem {
        AppItem(
            identifier: textColumn(statement, index: 0),
            bundleIdentifier: optionalTextColumn(statement, index: 1),
            name: textColumn(statement, index: 2),
            url: URL(fileURLWithPath: textColumn(statement, index: 3)),
            creationDate: nil,
            modificationDate: nil
        )
    }

    private func existingAssignment(for appIdentifier: String) throws -> ExistingAssignment? {
        let statement = try prepare(
            "SELECT folder_id, assignment_source FROM applications WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(appIdentifier)], to: statement)
        guard try step(statement) == SQLITE_ROW else { return nil }

        return ExistingAssignment(
            folderIdentifier: optionalTextColumn(statement, index: 0),
            source: AssignmentSource(rawValue: textColumn(statement, index: 1)) ?? .none
        )
    }

    /// A drag is planned from the visible catalog, so commit validation must reject an app that
    /// disappeared or changed containers while the delayed drop callback was pending. This is
    /// separate from the UPDATE itself: setting an unchanged sort position is still a valid
    /// arrangement and must not be mistaken for a stale row.
    private func presentApplicationExists(
        identifier: String,
        folderIdentifier: String?
    ) throws -> Bool {
        if let folderIdentifier {
            return try scalarInt64(
                """
                SELECT COUNT(*) FROM applications
                WHERE id = ? AND folder_id = ? AND is_present = 1
                """,
                values: [.text(identifier), .text(folderIdentifier)]
            ) > 0
        }
        return try scalarInt64(
            """
            SELECT COUNT(*) FROM applications
            WHERE id = ? AND folder_id IS NULL AND is_present = 1
            """,
            values: [.text(identifier)]
        ) > 0
    }

    private func setAssignment(
        appIdentifier: String,
        folderIdentifier: String?,
        position: Int64,
        source: AssignmentSource
    ) throws {
        try execute(
            """
            UPDATE applications
            SET folder_id = ?, sort_position = ?, assignment_source = ?
            WHERE id = ?
            """,
            [
                folderIdentifier.map(Value.text) ?? .null,
                .int64(position),
                .text(source.rawValue),
                .text(appIdentifier),
            ]
        )
    }

    private func folderSystemFlag(identifier: String) throws -> Bool? {
        let statement = try prepare("SELECT is_system FROM folders WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(identifier)], to: statement)
        guard try step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int(statement, 0) != 0
    }

    private func applicationIdentifiers(in folderIdentifier: String) throws -> [String] {
        let statement = try prepare(
            "SELECT id FROM applications WHERE folder_id = ? ORDER BY sort_position"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(folderIdentifier)], to: statement)

        var identifiers: [String] = []
        while try step(statement) == SQLITE_ROW {
            identifiers.append(textColumn(statement, index: 0))
        }
        return identifiers
    }

    private func nextApplicationPosition(folderIdentifier: String?) throws -> Int64 {
        let sql: String
        let values: [Value]
        if let folderIdentifier {
            sql = "SELECT COALESCE(MAX(sort_position), -1) + 1 FROM applications WHERE folder_id = ?"
            values = [.text(folderIdentifier)]
        } else {
            sql = "SELECT COALESCE(MAX(sort_position), -1) + 1 FROM applications WHERE folder_id IS NULL"
            values = []
        }
        return try scalarInt64(sql, values: values)
    }

    private func nextRootItemPosition() throws -> Int64 {
        try scalarInt64(
            """
            SELECT COALESCE(MAX(position), -1) + 1 FROM (
                SELECT sort_position AS position
                FROM applications
                WHERE folder_id IS NULL
                UNION ALL
                SELECT folders.sort_position AS position
                FROM folders
                WHERE folders.is_default = 0
                   OR folders.sort_position != \(Self.defaultOtherSortPosition)
                   OR EXISTS (
                       SELECT 1 FROM applications
                       WHERE applications.folder_id = folders.id
                         AND applications.is_present = 1
                   )
            )
            """,
            values: []
        )
    }

    private func nextUserFolderPosition() throws -> Int64 {
        try nextRootItemPosition()
    }

    private func scalarInt64(_ sql: String, values: [Value]) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard try step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(statement, 0)
    }

    private func withAccessLock<T>(_ body: () throws -> T) rethrows -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        return try body()
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)

        while true {
            let result = try step(statement)
            if result == SQLITE_DONE { return }
        }
    }

    /// Only SQLITE_ROW and SQLITE_DONE are normal sqlite3_step outcomes; propagate all others.
    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw sqliteError()
        }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw LunchpadLayoutStoreError.sqlite("Layout database is not open")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw sqliteError()
        }
        return statement
    }

    private func bind(_ values: [Value], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .int64(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .double(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw sqliteError() }
        }
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalTextColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return textColumn(statement, index: index)
    }

    private func sqliteError() -> LunchpadLayoutStoreError {
        guard let database else {
            return .sqlite("Layout database is not open")
        }
        return .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}

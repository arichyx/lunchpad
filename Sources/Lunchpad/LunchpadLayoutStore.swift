import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum LunchpadLayoutStoreError: Error, CustomStringConvertible {
    case sqlite(String)
    case invalidFolderName
    case folderNotFound
    case applicationNotFound
    case protectedSystemFolder

    var description: String {
        switch self {
        case .sqlite(let message): message
        case .invalidFolderName: "Folder name must not be empty"
        case .folderNotFound: "Folder not found"
        case .applicationNotFound: "Application not found"
        case .protectedSystemFolder: "System folders cannot be deleted or renamed"
        }
    }
}

/// Lunchpad's layout database. Finder paths locate apps; this store owns folder assignments.
final class LunchpadLayoutStore {
    static let otherFolderIdentifier = "system.other"

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

    private struct PositionedItem {
        let position: Int64
        let name: String
        let item: LunchpadItem
    }

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
    func reconcile(_ discoveredApplications: [DiscoveredApplication]) throws -> [LunchpadItem] {
        try transaction {
            try execute("UPDATE applications SET is_present = 0")

            var nextRootPosition = try nextApplicationPosition(folderIdentifier: nil)
            var nextOtherPosition = try nextApplicationPosition(
                folderIdentifier: Self.otherFolderIdentifier
            )
            let now = Date().timeIntervalSince1970

            for discovered in discoveredApplications {
                let app = discovered.item
                if let existing = try existingAssignment(for: app.identifier) {
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

                    // Only untouched root applications may receive the default Other assignment.
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
        }

        return try loadVisibleItems()
    }

    @discardableResult
    func createFolder(name rawName: String) throws -> String {
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

    func renameFolder(identifier: String, name rawName: String) throws {
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

    /// Deleting a logical folder removes assignments without touching app bundles on disk.
    func deleteFolder(identifier: String) throws {
        guard let isSystem = try folderSystemFlag(identifier: identifier) else {
            throw LunchpadLayoutStoreError.folderNotFound
        }
        guard !isSystem else { throw LunchpadLayoutStoreError.protectedSystemFolder }

        try transaction {
            var nextPosition = try nextApplicationPosition(folderIdentifier: nil)
            let memberIdentifiers = try applicationIdentifiers(in: identifier)
            for appIdentifier in memberIdentifiers {
                try setAssignment(
                    appIdentifier: appIdentifier,
                    folderIdentifier: nil,
                    position: nextPosition,
                    source: .user
                )
                nextPosition += 1
            }
            try execute("DELETE FROM folders WHERE id = ?", [.text(identifier)])
        }
    }

    /// A nil folderIdentifier moves the app to the root. User assignments prevent future
    /// scans from restoring a default folder.
    func assignApplication(
        identifier appIdentifier: String,
        toFolder folderIdentifier: String?
    ) throws {
        guard try existingAssignment(for: appIdentifier) != nil else {
            throw LunchpadLayoutStoreError.applicationNotFound
        }
        if let folderIdentifier,
           try folderSystemFlag(identifier: folderIdentifier) == nil {
            throw LunchpadLayoutStoreError.folderNotFound
        }

        let position = try nextApplicationPosition(folderIdentifier: folderIdentifier)
        try setAssignment(
            appIdentifier: appIdentifier,
            folderIdentifier: folderIdentifier,
            position: position,
            source: .user
        )
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

    private func migrate() throws {
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

    private func loadVisibleItems() throws -> [LunchpadItem] {
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

    private func nextUserFolderPosition() throws -> Int64 {
        try scalarInt64(
            """
            SELECT COALESCE(MAX(position), -1) + 1 FROM (
                SELECT sort_position AS position FROM applications WHERE folder_id IS NULL
                UNION ALL
                SELECT sort_position AS position FROM folders WHERE is_default = 0
            )
            """,
            values: []
        )
    }

    private func scalarInt64(_ sql: String, values: [Value]) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard try step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(statement, 0)
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

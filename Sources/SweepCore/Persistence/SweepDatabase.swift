import Foundation
import SQLiteData

public enum SweepDatabase {
    public static func openDefault() throws -> any DatabaseWriter {
        let databaseURL = try defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try open(at: databaseURL)
    }

    public static func open(at url: URL) throws -> any DatabaseWriter {
        let database = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Create torrents and settings") { db in
            try #sql(
                """
                CREATE TABLE "torrents" (
                  "id" INTEGER PRIMARY KEY NOT NULL,
                  "name" TEXT NOT NULL,
                  "infoHash" TEXT NOT NULL,
                  "magnet" TEXT,
                  "state" TEXT NOT NULL,
                  "progressBytes" INTEGER NOT NULL DEFAULT 0,
                  "totalBytes" INTEGER NOT NULL DEFAULT 0,
                  "uploadedBytes" INTEGER NOT NULL DEFAULT 0,
                  "downloadBps" REAL NOT NULL DEFAULT 0,
                  "uploadBps" REAL NOT NULL DEFAULT 0,
                  "error" TEXT
                ) STRICT
                """
            )
            .execute(db)

            try #sql(
                """
                CREATE TABLE "appSettings" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "value" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }
        migrator.registerMigration("Use info hash torrent identity") { db in
            try #sql(
                """
                CREATE TABLE "new_torrents" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "engineID" INTEGER,
                  "name" TEXT NOT NULL,
                  "infoHash" TEXT NOT NULL,
                  "magnet" TEXT,
                  "downloadDirectory" TEXT,
                  "desiredState" TEXT NOT NULL DEFAULT 'running',
                  "state" TEXT NOT NULL,
                  "progressBytes" INTEGER NOT NULL DEFAULT 0,
                  "totalBytes" INTEGER NOT NULL DEFAULT 0,
                  "uploadedBytes" INTEGER NOT NULL DEFAULT 0,
                  "downloadBps" REAL NOT NULL DEFAULT 0,
                  "uploadBps" REAL NOT NULL DEFAULT 0,
                  "error" TEXT,
                  "addedAt" REAL NOT NULL DEFAULT 0,
                  "updatedAt" REAL NOT NULL DEFAULT 0
                ) STRICT
                """
            )
            .execute(db)

            try #sql(
                """
                INSERT OR REPLACE INTO "new_torrents" (
                  "id",
                  "engineID",
                  "name",
                  "infoHash",
                  "magnet",
                  "desiredState",
                  "state",
                  "progressBytes",
                  "totalBytes",
                  "uploadedBytes",
                  "downloadBps",
                  "uploadBps",
                  "error",
                  "addedAt",
                  "updatedAt"
                )
                SELECT
                  LOWER("infoHash"),
                  "id",
                  "name",
                  LOWER("infoHash"),
                  "magnet",
                  CASE WHEN LOWER("state") = 'paused' THEN 'paused' ELSE 'running' END,
                  "state",
                  "progressBytes",
                  "totalBytes",
                  "uploadedBytes",
                  "downloadBps",
                  "uploadBps",
                  "error",
                  CAST(strftime('%s', 'now') AS REAL),
                  CAST(strftime('%s', 'now') AS REAL)
                FROM "torrents"
                """
            )
            .execute(db)

            try #sql("DROP TABLE \"torrents\"")
                .execute(db)
            try #sql("ALTER TABLE \"new_torrents\" RENAME TO \"torrents\"")
                .execute(db)
        }
        migrator.registerMigration("Store torrent file sources") { db in
            try #sql("ALTER TABLE \"torrents\" ADD COLUMN \"torrentFileName\" TEXT")
                .execute(db)
            try #sql("ALTER TABLE \"torrents\" ADD COLUMN \"torrentFileBytes\" BLOB")
                .execute(db)
        }
        migrator.registerMigration("Store torrent file metadata") { db in
            try #sql("ALTER TABLE \"torrents\" ADD COLUMN \"files\" TEXT")
                .execute(db)
        }
        migrator.registerMigration("Store torrent tracker metadata") { db in
            try #sql("ALTER TABLE \"torrents\" ADD COLUMN \"trackers\" TEXT")
                .execute(db)
        }
        migrator.registerMigration("Remove UI display settings") { db in
            try #sql("DELETE FROM \"appSettings\" WHERE \"id\" = 'visibleTorrentColumns'")
                .execute(db)
        }
        try migrator.migrate(database)
        return database
    }

    private static func defaultDatabaseURL() throws -> URL {
        try FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "Sweep", directoryHint: .isDirectory)
            .appending(path: "Sweep.sqlite")
    }
}

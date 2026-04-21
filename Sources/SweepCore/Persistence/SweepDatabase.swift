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

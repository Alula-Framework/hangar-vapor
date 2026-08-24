import Foundation
import Hangar
import PostgresNIO
import Testing
import Vapor
import VaporTesting

@testable import HangarVapor

/// The integration gate. These tests are about a real pool inside a real
/// application; there is nothing worth asserting against a fake.
///
///   HANGAR_VAPOR_TEST_DATABASE_URL=postgres://user:pass@host:5432/db swift test
///
/// Falls back to `HANGAR_TEST_DATABASE_URL`, so hangar's own contributor
/// setup works here unchanged.
enum TestDatabase {
    static var url: String? {
        for key in ["HANGAR_VAPOR_TEST_DATABASE_URL", "HANGAR_TEST_DATABASE_URL"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static var isAvailable: Bool { url != nil }

    /// Parses the URL into the shape `PostgresClient` wants.
    static func configuration() throws -> PostgresClient.Configuration {
        guard let raw = url, let parsed = URL(string: raw) else {
            throw ConfigurationError.missing
        }
        return PostgresClient.Configuration(
            host: parsed.host ?? "localhost",
            port: parsed.port ?? 5432,
            username: parsed.user ?? "postgres",
            password: parsed.password,
            database: parsed.path.isEmpty ? nil : String(parsed.path.dropFirst()),
            tls: .disable)
    }

    enum ConfigurationError: Error { case missing }
}

/// The one fixture table. Created and truncated per test.
@Entity("hangar_vapor_widgets")
struct Widget: Sendable, Equatable {
    @ID let id: UUID
    var name: String
}

/// Serializes fixture use across suites.
///
/// Two suites running at once both reach for the same table, and
/// `CREATE TABLE IF NOT EXISTS` is not safe against itself — concurrent
/// calls race in `pg_type` and one fails on a unique violation. TRUNCATE
/// has the same problem for the opposite reason: it would empty the table
/// under another suite's rows. One lock owns both. Same shape as hangar's
/// own `DatabaseLock`, for the same reason.
actor DatabaseFixture {
    static let shared = DatabaseFixture()

    private var created = false
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    private func prepare(_ repo: Repo) async throws {
        if !created {
            _ = try await repo.execute(
                #"""
                CREATE TABLE IF NOT EXISTS "hangar_vapor_widgets" (
                    "id" uuid PRIMARY KEY,
                    "name" text NOT NULL
                )
                """#)
            created = true
        }
        _ = try await repo.execute(#"TRUNCATE "hangar_vapor_widgets""#)
    }

    /// Runs `body` with a clean fixture table nobody else is using.
    func exclusive<T: Sendable>(
        preparing repo: Repo, _ body: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        defer { release() }
        try await prepare(repo)
        return try await body()
    }
}

/// Boots an application with Hangar configured and a clean fixture table.
///
/// The whole body runs under ``DatabaseFixture``, so two suites never share
/// the table's contents.
func withHangarApp<T: Sendable>(
    configure extra: (@Sendable (Application) async throws -> Void)? = nil,
    _ test: @Sendable (Application) async throws -> T
) async throws -> T {
    try await withApp { app in
        app.hangar.use(try TestDatabase.configuration())
        // The pool is lazy: the first statement is what proves it started.
        return try await DatabaseFixture.shared.exclusive(preparing: app.hangar.repo) {
            try await extra?(app)
            return try await test(app)
        }
    }
}

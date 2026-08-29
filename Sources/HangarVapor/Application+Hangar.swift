import Hangar
import PostgresNIO
import Vapor

// The application half: one `PostgresClient`, started with the app and
// stopped with it.
//
// Hangar takes a connection source and nothing else — it has no idea what a
// request is. That is what keeps it framework-independent, and it is also
// why an integration is needed at all: somebody has to own the client's
// lifetime and hand each request a repo that logs under that request's ID.

extension Application {

    /// Hangar's application-level configuration and its shared repo.
    ///
    /// ```swift
    /// // configure.swift
    /// try app.hangar.use(.init(
    ///     host: Environment.get("DATABASE_HOST") ?? "localhost",
    ///     username: "postgres", password: "postgres", database: "app",
    ///     tls: .disable))
    /// ```
    public var hangar: HangarService { HangarService(application: self) }

    /// The application-scoped Hangar surface — configuration, the shared
    /// ``Hangar/Repo``, and the client's lifetime.
    public struct HangarService: Sendable {
        let application: Application

        // Internal rather than private so a test can assert the pool task is
        // cancelled at shutdown — a leak here outlives the application.
        struct ClientKey: StorageKey, Sendable {
            typealias Value = RunningClient
        }

        /// The client plus the task running its connection pool. Boxed in a
        /// class so `shutdown` can cancel the task Vapor's storage is
        /// holding.
        final class RunningClient: Sendable {
            let client: PostgresClient
            let task: Task<Void, Never>

            // No logger parameter: `PostgresClient` was handed its
            // `backgroundLogger` at construction, so one here was only ever
            // an unused argument at the single call site.
            init(client: PostgresClient) {
                self.client = client
                // PostgresClient does nothing until `run()` is running: it
                // is the pool. Detached because it must outlive whatever
                // task called `use`, and cancelled in `shutdown`.
                self.task = Task.detached { await client.run() }
            }
        }

        /// Configures the database and starts the connection pool.
        ///
        /// Call it once, from `configure(_:)`. The pool is shut down when
        /// the application is.
        ///
        /// - Parameters:
        ///   - configuration: the PostgresNIO client configuration.
        ///   - backgroundLogger: where the pool's own messages go. Per-query
        ///     logging uses the *request's* logger instead — see
        ///     ``Vapor/Request/hangar``.
        public func use(
            _ configuration: PostgresClient.Configuration,
            backgroundLogger: Logger? = nil
        ) {
            let logger = backgroundLogger ?? application.logger
            let client = PostgresClient(configuration: configuration, backgroundLogger: logger)
            let running = RunningClient(client: client)
            application.storage[ClientKey.self] = running
            application.lifecycle.use(Lifecycle())
        }

        /// The client, or a trap naming the missing configuration call.
        ///
        /// Trapping rather than throwing on purpose: reaching a repo with no
        /// database configured is a wiring mistake in `configure(_:)` that
        /// every request would hit, not a runtime condition a handler can
        /// recover from.
        public var client: PostgresClient {
            guard let running = application.storage[ClientKey.self] else {
                fatalError(
                    """
                    Hangar has no database. Call `app.hangar.use(...)` in configure(_:) \
                    before the first request.
                    """)
            }
            return running.client
        }

        /// A repo over the shared pool, logging to the application's logger.
        ///
        /// For boot-time work — migrations, seeding, a warmup query. Inside
        /// a request handler use ``Vapor/Request/hangar`` instead, so query
        /// logs carry the request's ID.
        public var repo: Repo {
            Repo(client: client, logger: application.logger)
        }

        struct Lifecycle: LifecycleHandler {
            func shutdown(_ application: Application) {
                application.storage[ClientKey.self]?.task.cancel()
            }
        }
    }
}

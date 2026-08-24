import Hangar
import Vapor

// The request half: a repo that logs under this request's ID, and the two
// scoping helpers a handler actually reaches for.

extension Request {

    /// A repo over the application's pool, logging under this request's ID.
    ///
    /// ```swift
    /// app.get("posts") { req async throws -> [Post] in
    ///     try await req.hangar.all(Post.where { $0.published == true })
    /// }
    /// ```
    ///
    /// Each statement takes a connection from the pool and returns it — the
    /// request does not hold one for its lifetime. That is deliberate: a
    /// handler that awaits an HTTP call between two queries should not be
    /// pinning a connection while it waits. When a run of statements *must*
    /// share one connection, that is what ``transaction(_:)`` is for.
    public var hangar: Repo {
        Repo(client: application.hangar.client, logger: logger)
    }

    /// Runs `body` inside a transaction on one connection, with the repo
    /// also installed as ``Hangar/Repo/current`` for its duration.
    ///
    /// ```swift
    /// app.post("orders") { req async throws -> Order in
    ///     try await req.transaction { db in
    ///         let order = try await db.insert(Order(...))
    ///         try await db.insert(LineItem(orderID: order.id, ...))
    ///         return order
    ///     }
    /// }
    /// ```
    ///
    /// Throwing from `body` rolls back. Nested calls become savepoints.
    ///
    /// The ambient binding means a service or repository type that calls
    /// `Repo.require()` joins this transaction without the handler
    /// threading a repo through every signature. It propagates to
    /// structured child tasks and *not* across `Task.detached` — a
    /// background job must not silently join a request's transaction.
    public func transaction<T: Sendable>(
        _ body: (Repo) async throws -> T
    ) async throws -> T {
        try await hangar.transaction { db in
            try await Repo.with(db) {
                try await body(db)
            }
        }
    }

    /// Runs `body` with this request's repo installed as
    /// ``Hangar/Repo/current``, without opening a transaction.
    ///
    /// The read-path counterpart to ``transaction(_:)``: code that calls
    /// `Repo.require()` works, and each statement still takes a pooled
    /// connection independently.
    ///
    /// ```swift
    /// app.get("dashboard") { req async throws -> View in
    ///     try await req.withHangar { try await DashboardService().render() }
    /// }
    /// ```
    public func withHangar<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        try await Repo.with(hangar, body)
    }
}

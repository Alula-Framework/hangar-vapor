# HangarVapor

[Hangar](https://github.com/Flight-Framework/hangar) in a Vapor application.

Hangar is a Postgres query layer built directly on PostgresNIO. It has no
framework coupling — `Repo` takes a connection source and nothing else —
which is what makes it usable from Vapor at all, and also why this small
package exists: somebody has to own the connection pool's lifetime and hand
each request a repo that logs under that request's ID.

**You do not have to leave Vapor or Fluent to use it.** Keep Fluent for the
models it handles well and reach for Hangar where Fluent's query builder
runs out — a three-table join, `DISTINCT ON`, a recursive CTE, a projection
into a struct that is not a model, a bulk update that returns the rows it
touched. They share a database and coexist in the same handler.

## Status

Early. The surface is three things and unlikely to grow much; what will
change is what Hangar itself gains underneath. Requires hangar 0.3.0 or
later.

To develop against a hangar checkout rather than the published tag — when a
change is landing in both at once:

```bash
./scripts/dev-link.sh ../hangar     # point Package.swift at a local hangar
./scripts/dev-link.sh --undo        # put the published tag back
```

## Installation

```swift
.package(url: "https://github.com/Flight-Framework/hangar-vapor.git", from: "0.1.0"),
```

```swift
.product(name: "HangarVapor", package: "hangar-vapor"),
```

## Configuring

Once, in `configure(_:)`:

```swift
import HangarVapor

public func configure(_ app: Application) async throws {
    app.hangar.use(.init(
        host: Environment.get("DATABASE_HOST") ?? "localhost",
        port: 5432,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor",
        password: Environment.get("DATABASE_PASSWORD"),
        database: Environment.get("DATABASE_NAME") ?? "vapor",
        tls: .disable))
}
```

The pool starts with the call and is cancelled when the application shuts
down.

## In a handler

```swift
app.get("posts") { req async throws -> [Post] in
    try await req.hangar.all(
        Post.where { $0.published == true }
            .order { $0.publishedAt.desc() }
            .limit(20))
}
```

`req.hangar` is a `Repo` over the shared pool carrying the request's logger,
so every query Hangar logs is stamped with the request ID.

Each statement takes a connection from the pool and gives it straight back —
the request does not hold one for its lifetime. That is deliberate: a handler
awaiting an HTTP call between two queries should not be pinning a connection
while it waits.

## Transactions

```swift
app.post("orders") { req async throws -> Order in
    try await req.transaction { db in
        let order = try await db.insert(Order(...))
        try await db.insert(LineItem(orderID: order.id, ...))
        return order
    }
}
```

Everything inside runs on one connection. Throwing rolls back. Nesting
becomes a savepoint, so an inner failure can be caught without losing the
outer work.

## Services that do not take a repo parameter

`req.transaction` also installs the repo as `Repo.current` for the duration
of the body, so a service or repository type can reach it without every
signature threading a repo through:

```swift
struct OrderService {
    func place(_ input: OrderInput) async throws -> Order {
        let db = try Repo.require()
        let order = try await db.insert(Order(from: input))
        try await db.insert(LineItem(orderID: order.id, ...))
        return order
    }
}

app.post("orders") { req async throws -> Order in
    try await req.transaction { _ in try await OrderService().place(input) }
}
```

`req.withHangar { }` is the read-path counterpart: same ambient binding, no
`BEGIN`.

The binding propagates to structured child tasks (`async let`, task groups)
and **not** across `Task.detached` — which is correct. A background job must
not silently join a request's transaction and become durable when that
request commits.

## What is not here

No Fluent bridge — the two are separate query layers over the same database,
and pretending otherwise would mean reimplementing one in terms of the other.
No migrations; use whatever you already use. No `EventLoopFuture` API — this
is `async`/`await` only, like Hangar itself.

## Running the tests

The tests are about a real pool inside a real application, so they need a
database:

```bash
./scripts/test.sh          # starts a throwaway Postgres, runs everything
```

Or point at your own:

```bash
HANGAR_VAPOR_TEST_DATABASE_URL=postgres://user:pass@localhost:5432/db swift test
```

## License

MIT. See [LICENSE](LICENSE).

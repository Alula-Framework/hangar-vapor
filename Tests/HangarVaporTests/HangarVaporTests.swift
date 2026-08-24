import Foundation
import Hangar
import Testing
import Vapor
import VaporTesting

@testable import HangarVapor

@Suite("Hangar in a Vapor application", .serialized,
       .enabled(if: TestDatabase.isAvailable,
                "set HANGAR_VAPOR_TEST_DATABASE_URL (or HANGAR_TEST_DATABASE_URL)"))
struct HangarVaporTests {

    @Test("a handler queries through req.hangar")
    func requestRepo() async throws {
        try await withHangarApp { app in
            app.get("widgets") { req async throws -> [String] in
                try await req.hangar.all(Widget.all.order { $0.name.asc() }).map(\.name)
            }

            _ = try await app.hangar.repo.insert(Widget(id: UUID(), name: "b"))
            _ = try await app.hangar.repo.insert(Widget(id: UUID(), name: "a"))

            try await app.testing().test(.GET, "widgets") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == #"["a","b"]"#)
            }
        }
    }

    @Test("req.hangar logs under the request's logger, not the application's")
    func perRequestLogger() async throws {
        try await withHangarApp { app in
            app.get("who") { req async throws -> String in
                // The repo carries the request's logger, which carries the
                // request ID — that is the whole reason `req.hangar` exists
                // rather than handlers reaching for `app.hangar.repo`.
                let expected = req.logger[metadataKey: "request-id"]
                #expect(expected != nil)
                _ = try await req.hangar.count(Widget.all)
                return "ok"
            }
            try await app.testing().test(.GET, "who") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("req.transaction commits on return")
    func transactionCommits() async throws {
        try await withHangarApp { app in
            app.post("pair") { req async throws -> String in
                try await req.transaction { db in
                    _ = try await db.insert(Widget(id: UUID(), name: "one"))
                    _ = try await db.insert(Widget(id: UUID(), name: "two"))
                    return "ok"
                }
            }

            try await app.testing().test(.POST, "pair") { res async in
                #expect(res.status == .ok)
            }
            #expect(try await app.hangar.repo.count(Widget.all) == 2)
        }
    }

    @Test("req.transaction rolls back when the handler throws")
    func transactionRollsBack() async throws {
        try await withHangarApp { app in
            app.post("fail") { req async throws -> String in
                try await req.transaction { db in
                    _ = try await db.insert(Widget(id: UUID(), name: "doomed"))
                    throw Abort(.badRequest)
                }
            }

            try await app.testing().test(.POST, "fail") { res async in
                #expect(res.status == .badRequest)
            }
            #expect(try await app.hangar.repo.count(Widget.all) == 0,
                    "the insert must not have survived the throw")
        }
    }

    @Test("a service reaching for the ambient repo joins the request's transaction")
    func ambientJoinsTheTransaction() async throws {
        // The point of the ambient binding: a service type does not take a
        // repo parameter, and still writes inside the handler's transaction
        // — so its work rolls back with everything else.
        struct WidgetService {
            func add(_ name: String) async throws {
                _ = try await Repo.require().insert(Widget(id: UUID(), name: name))
            }
        }

        try await withHangarApp { app in
            app.post("service-fail") { req async throws -> String in
                try await req.transaction { _ in
                    try await WidgetService().add("from-service")
                    throw Abort(.conflict)
                }
            }
            app.post("service-ok") { req async throws -> String in
                try await req.transaction { _ in
                    try await WidgetService().add("from-service")
                    return "ok"
                }
            }

            try await app.testing().test(.POST, "service-fail") { res async in
                #expect(res.status == .conflict)
            }
            #expect(try await app.hangar.repo.count(Widget.all) == 0)

            try await app.testing().test(.POST, "service-ok") { res async in
                #expect(res.status == .ok)
            }
            #expect(try await app.hangar.repo.count(Widget.all) == 1)
        }
    }

    @Test("withHangar binds the ambient repo without opening a transaction")
    func withHangarBindsWithoutTransaction() async throws {
        try await withHangarApp { app in
            app.get("ambient") { req async throws -> String in
                try await req.withHangar {
                    let repo = try Repo.require()
                    #expect(!repo.isInTransaction, "no BEGIN was asked for")
                    _ = try await repo.insert(Widget(id: UUID(), name: "ambient"))
                    return "ok"
                }
            }

            try await app.testing().test(.GET, "ambient") { res async in
                #expect(res.status == .ok)
            }
            // No transaction was opened, so the write stands on its own.
            #expect(try await app.hangar.repo.count(Widget.all) == 1)
        }
    }

    @Test("no ambient repo outside a scope — a detached job does not join a request")
    func noAmbientOutsideAScope() async throws {
        try await withHangarApp { _ in
            #expect(throws: HangarError.self) { _ = try Repo.require() }
        }
    }

    @Test("a nested transaction becomes a savepoint")
    func nestedIsASavepoint() async throws {
        try await withHangarApp { app in
            app.post("nested") { req async throws -> String in
                try await req.transaction { db in
                    _ = try await db.insert(Widget(id: UUID(), name: "outer"))
                    // The inner failure unwinds to its savepoint only.
                    try? await db.transaction { inner in
                        _ = try await inner.insert(Widget(id: UUID(), name: "inner"))
                        throw Abort(.badRequest)
                    }
                    return "ok"
                }
            }

            try await app.testing().test(.POST, "nested") { res async in
                #expect(res.status == .ok)
            }
            let names = try await app.hangar.repo.all(Widget.all).map(\.name)
            #expect(names == ["outer"])
        }
    }
}

@Suite("Lifecycle",
       .enabled(if: TestDatabase.isAvailable,
                "set HANGAR_VAPOR_TEST_DATABASE_URL (or HANGAR_TEST_DATABASE_URL)"))
struct LifecycleTests {

    @Test("shutting the application down cancels the pool task")
    func shutdownCancelsThePool() async throws {
        let captured: Task<Void, Never> = try await withHangarApp { app in
            let task = app.storage[Application.HangarService.ClientKey.self]?.task
            #expect(task?.isCancelled == false, "the pool is running while the app is")
            return try #require(task)
        }
        // `withApp` shut the application down on the way out.
        #expect(captured.isCancelled, "a leaked pool task outlives its application")
    }
}

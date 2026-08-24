// The README's examples, as code the build compiles.
//
// A README that shows an API is a claim about that API. Every shape below
// appears in README.md, so a signature change breaks the build here rather
// than only misleading a reader.
import Foundation
import Hangar
import HangarVapor
import Vapor

// snippet.hide
@Entity("posts")
struct Post: Sendable, Content {
    @ID var id: UUID
    var published: Bool
    @Column("published_at") var publishedAt: Date
}

@Entity("orders")
struct Order: Sendable, Content {
    @ID var id: UUID
    var total: Int
}

@Entity("line_items")
struct LineItem: Sendable {
    @ID var id: UUID
    @Column("order_id") var orderID: UUID
    var sku: String
}

struct OrderInput: Sendable { var total: Int }

extension Order {
    init(from input: OrderInput) { self.init(id: UUID(), total: input.total) }
}
// snippet.show

func configureExample(_ app: Application) async throws {
    app.hangar.use(
        .init(
            host: Environment.get("DATABASE_HOST") ?? "localhost",
            port: 5432,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor",
            password: Environment.get("DATABASE_PASSWORD"),
            database: Environment.get("DATABASE_NAME") ?? "vapor",
            tls: .disable))
}

struct OrderService {
    func place(_ input: OrderInput) async throws -> Order {
        let db = try Repo.require()
        let order = try await db.insert(Order(from: input))
        try await db.insert(LineItem(id: UUID(), orderID: order.id, sku: "x"))
        return order
    }
}

func routesExample(_ app: Application) {
    app.get("posts") { req async throws -> [Post] in
        try await req.hangar.all(
            Post.where { $0.published == true }
                .order { $0.publishedAt.desc() }
                .limit(20))
    }

    app.post("orders") { req async throws -> Order in
        try await req.transaction { db in
            let order = try await db.insert(Order(id: UUID(), total: 1))
            try await db.insert(LineItem(id: UUID(), orderID: order.id, sku: "x"))
            return order
        }
    }

    app.post("orders", "via-service") { req async throws -> Order in
        let input = OrderInput(total: 1)
        return try await req.transaction { _ in try await OrderService().place(input) }
    }

    app.get("dashboard") { req async throws -> String in
        try await req.withHangar {
            _ = try await Repo.require().count(Post.all)
            return "ok"
        }
    }
}

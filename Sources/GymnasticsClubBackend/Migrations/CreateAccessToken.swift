import Fluent
struct CreateAccessToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("access_tokens").id()
            .field("user_id", .uuid, .required, .references("admin_users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime, .required)
            .unique(on: "token_hash").create()
    }
    func revert(on database: any Database) async throws { try await database.schema("access_tokens").delete() }
}

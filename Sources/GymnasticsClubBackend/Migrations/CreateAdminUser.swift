import Fluent
struct CreateAdminUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("admin_users").id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "email").create()
    }
    func revert(on database: any Database) async throws { try await database.schema("admin_users").delete() }
}

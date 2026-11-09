import Fluent

struct CreateCoach: Migration {
    func prepare(on database: any Database) -> EventLoopFuture<Void> {
        database.schema("coaches")
            .id()
            .field("full_name", .string, .required)
            .unique(on: "full_name")
            .field("specialty", .string, .required)
            .create()
    }

    func revert(on database: any Database) -> EventLoopFuture<Void> {
        database.schema("coaches").delete()
    }
}

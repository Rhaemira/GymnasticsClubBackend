import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "loki",
        password: Environment.get("DATABASE_PASSWORD") ?? "",
        database: Environment.get("DATABASE_NAME") ?? "gymnastics_club",
        tls: .prefer(try .init(configuration: .clientDefault)))
    ), as: .psql)

    app.migrations.add(CreateCoach())
    app.migrations.add(CreateAthlete())
    app.migrations.add(CreateClass())
    app.migrations.add(CreateEnrollment())
    app.migrations.add(CreateAttendance())
 // ← patches live FK constraints
    app.commands.use(SeedData(), as: "seed")

    try routes(app)

}

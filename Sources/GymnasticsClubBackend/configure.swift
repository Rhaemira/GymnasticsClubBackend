import Fluent
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {
    guard let host = Environment.get("DATABASE_HOST"),
          let portString = Environment.get("DATABASE_PORT"), let port = Int(portString),
          let username = Environment.get("DATABASE_USERNAME"),
          let password = Environment.get("DATABASE_PASSWORD"),
          let database = Environment.get("DATABASE_NAME"),
          !host.isEmpty, !username.isEmpty, !database.isEmpty else {
        throw Abort(.internalServerError, reason: "Database configuration incomplete. Set DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USERNAME and DATABASE_PASSWORD.")
    }

    let tlsMode = Environment.get("DATABASE_TLS")?.lowercased() ?? "prefer"
    guard ["disable", "prefer", "require"].contains(tlsMode) else {
        throw Abort(.internalServerError, reason: "DATABASE_TLS must be disable, prefer or require.")
    }
    let tls: PostgresConfiguration.TLS
    switch tlsMode {
    case "disable": tls = .disable
    case "require": tls = .require(try .init(configuration: .clientDefault))
    default: tls = .prefer(try .init(configuration: .clientDefault))
    }

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: host, port: port, username: username, password: password, database: database, tls: tls
    )), as: .psql)

    app.migrations.add(CreateCoach())
    app.migrations.add(CreateAthlete())
    app.migrations.add(CreateClass())
    app.migrations.add(CreateEnrollment())
    app.migrations.add(CreateAttendance())
    // FixCascadeDeletes is intentionally NOT registered: its prepare() drops populated tables.
    app.migrations.add(CreateAdminUser())
    app.migrations.add(CreateAccessToken())

    app.commands.use(SeedData(), as: "seed")
    app.commands.use(CreateAdminCommand(), as: "create-admin")
    app.middleware.use(SecurityHeadersMiddleware())
    try routes(app)
}

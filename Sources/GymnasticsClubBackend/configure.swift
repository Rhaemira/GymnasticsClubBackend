import Foundation
import Fluent
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {
    guard let host = Environment.get("DATABASE_HOST"),
          let portString = Environment.get("DATABASE_PORT"), let port = Int(portString),
          let username = Environment.get("DATABASE_USERNAME"),
          let password = Environment.get("DATABASE_PASSWORD"),
          let database = Environment.get("DATABASE_NAME"),
          !host.isEmpty, !username.isEmpty, !password.isEmpty, !database.isEmpty, (1...65535).contains(port) else {
        throw Abort(.internalServerError, reason: "Database configuration incomplete. Set DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USERNAME and DATABASE_PASSWORD.")
    }

    guard let tokenTTL = Int(Environment.get("AUTH_TOKEN_TTL_SECONDS") ?? "43200"),
          (900...86400).contains(tokenTTL) else {
        throw Abort(.internalServerError, reason: "AUTH_TOKEN_TTL_SECONDS must be an integer between 900 and 86400.")
    }

    let defaultTLS = app.environment == .production ? "require" : "prefer"
    let tlsMode = Environment.get("DATABASE_TLS")?.lowercased() ?? defaultTLS
    guard ["disable", "prefer", "require"].contains(tlsMode) else {
        throw Abort(.internalServerError, reason: "DATABASE_TLS must be disable, prefer or require.")
    }

    // Production connections require TLS, except for the explicitly isolated
    // Docker Compose database service on its private, unpublished bridge network.
    let approvedPrivateComposeLink =
        host == "db" &&
        tlsMode == "disable" &&
        Environment.get("DATABASE_TLS_ALLOW_PRIVATE_COMPOSE_LINK") == "true"
    guard app.environment != .production || tlsMode == "require" || approvedPrivateComposeLink else {
        throw Abort(
            .internalServerError,
            reason: "Production PostgreSQL connections require DATABASE_TLS=require. The only exception is the isolated Compose database service."
        )
    }

    var databaseURL = URLComponents()
    databaseURL.scheme = "postgres"
    databaseURL.host = host
    databaseURL.port = port
    databaseURL.user = username
    databaseURL.password = password
    databaseURL.path = "/\(database)"
    databaseURL.queryItems = [URLQueryItem(name: "tlsmode", value: tlsMode)]
    guard let connectionURL = databaseURL.url else {
        throw Abort(.internalServerError, reason: "PostgreSQL connection settings are invalid.")
    }
    app.databases.use(try DatabaseConfigurationFactory.postgres(url: connectionURL), as: .psql)

    ContentConfiguration.global.use(encoder: BackendDateCoding.makeEncoder(), for: .json)
    ContentConfiguration.global.use(decoder: BackendDateCoding.makeDecoder(), for: .json)

    app.migrations.add(CreateCoach())
    app.migrations.add(CreateAthlete())
    app.migrations.add(CreateClass())
    app.migrations.add(CreateEnrollment())
    app.migrations.add(CreateAttendance())
    // FixCascadeDeletes is intentionally NOT registered: its prepare() drops populated tables.
    app.migrations.add(CreateAdminUser())
    app.migrations.add(CreateAccessToken())
    app.migrations.add(EnforceEnrollmentCapacity())
    app.migrations.add(EnforceClassCapacityRange())
    app.migrations.add(EnforceAttendanceUniqueness())

    app.asyncCommands.use(SeedData(), as: "seed")
    app.asyncCommands.use(CreateAdminCommand(), as: "create-admin")
    app.middleware.use(SecurityHeadersMiddleware())
    app.storage[LoginRateLimiterKey.self] = LoginRateLimiter()
    try routes(app)
}

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
          !host.isEmpty, !username.isEmpty, !database.isEmpty else {
        throw Abort(.internalServerError, reason: "Database configuration incomplete. Set DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USERNAME and DATABASE_PASSWORD.")
    }

    let defaultTLS = app.environment == .production ? "require" : "prefer"
    let tlsMode = Environment.get("DATABASE_TLS")?.lowercased() ?? defaultTLS
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

    let jsonEncoder = JSONEncoder()
    let outputFormatter = ISO8601DateFormatter()
    outputFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    jsonEncoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(outputFormatter.string(from: date))
    }

    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected ISO-8601 UTC timestamp.")
    }
    ContentConfiguration.global.use(encoder: jsonEncoder, decoder: jsonDecoder, for: .json)

    app.migrations.add(CreateCoach())
    app.migrations.add(CreateAthlete())
    app.migrations.add(CreateClass())
    app.migrations.add(CreateEnrollment())
    app.migrations.add(CreateAttendance())
    // FixCascadeDeletes is intentionally NOT registered: its prepare() drops populated tables.
    app.migrations.add(CreateAdminUser())
    app.migrations.add(CreateAccessToken())
    app.migrations.add(EnforceEnrollmentCapacity())

    app.commands.use(SeedData(), as: "seed")
    app.commands.use(CreateAdminCommand(), as: "create-admin")
    app.middleware.use(SecurityHeadersMiddleware())
    try routes(app)
}

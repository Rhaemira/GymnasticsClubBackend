import Fluent
import Vapor
import SQLKit

/// Adds indexes for the API's frequent enrollment, attendance and analytics joins.
struct AddQueryIndexes: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Query index migration requires PostgreSQL.")
        }

        try await sql.raw("CREATE INDEX IF NOT EXISTS enrollments_class_id_idx ON enrollments (class_id);").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS enrollments_athlete_id_idx ON enrollments (athlete_id);").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS classes_coach_id_idx ON classes (coach_id);").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS attendance_class_id_idx ON attendance (class_id);").run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS attendance_class_id_idx;").run()
        try await sql.raw("DROP INDEX IF EXISTS classes_coach_id_idx;").run()
        try await sql.raw("DROP INDEX IF EXISTS enrollments_athlete_id_idx;").run()
        try await sql.raw("DROP INDEX IF EXISTS enrollments_class_id_idx;").run()
    }
}

import Fluent
import SQLKit
import Vapor

/// Adds database-enforced attendance uniqueness without deleting or rewriting
/// attendance history. Existing duplicates stop the migration with an actionable
/// error so an operator can review and reconcile records before retrying.
struct EnforceAttendanceUniqueness: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Attendance uniqueness migration requires PostgreSQL.")
        }

        try await sql.raw("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM attendance
                    GROUP BY athlete_id, class_id, attended_on
                    HAVING COUNT(*) > 1
                ) THEN
                    RAISE EXCEPTION
                        'attendance_unique_athlete_class_timestamp: duplicate attendance rows exist; review them before applying this migration';
                END IF;
            END
            $$;
            """).run()

        try await sql.raw("""
            CREATE UNIQUE INDEX IF NOT EXISTS attendance_unique_athlete_class_timestamp
            ON attendance (athlete_id, class_id, attended_on);
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS attendance_unique_athlete_class_timestamp;").run()
    }
}

import Fluent
import Vapor
import SQLKit

/// Adds a database-level capacity bound without changing historical data.
/// Existing invalid data aborts migration with an actionable message.
struct EnforceClassCapacityRange: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Class capacity migration requires PostgreSQL.")
        }

        try await sql.raw("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM classes WHERE capacity NOT BETWEEN 1 AND 500
                ) THEN
                    RAISE EXCEPTION
                        'class_capacity_range_invalid: existing classes have capacity outside 1...500; review them before applying this migration';
                END IF;

                IF EXISTS (
                    SELECT c.id
                    FROM classes c
                    LEFT JOIN enrollments e ON e.class_id = c.id
                    GROUP BY c.id, c.capacity
                    HAVING COUNT(e.id) > c.capacity
                ) THEN
                    RAISE EXCEPTION
                        'class_capacity_below_enrollment: existing classes exceed their configured capacity; reconcile enrollment data before applying this migration';
                END IF;
            END
            $$;
            """).run()

        try await sql.raw("""
            ALTER TABLE classes
            ADD CONSTRAINT classes_capacity_range
            CHECK (capacity BETWEEN 1 AND 500);
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_capacity_range;").run()
    }
}

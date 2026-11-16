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

        let invalidCapacityRow = try await sql.raw("""
            SELECT COUNT(*) AS count
            FROM classes
            WHERE capacity NOT BETWEEN 1 AND 500
            """).first()
        let invalidCapacityCount = try invalidCapacityRow?.decode(column: "count", as: Int64.self) ?? 0
        guard invalidCapacityCount == 0 else {
            throw Abort(.internalServerError, reason: "Existing classes have capacity outside 1...500; review them before applying this migration.")
        }

        let overCapacityRow = try await sql.raw("""
            SELECT COUNT(*) AS count
            FROM (
                SELECT c.id
                FROM classes c
                LEFT JOIN enrollments e ON e.class_id = c.id
                GROUP BY c.id, c.capacity
                HAVING COUNT(e.id) > c.capacity
            ) AS invalid_classes
            """).first()
        let overCapacityCount = try overCapacityRow?.decode(column: "count", as: Int64.self) ?? 0
        guard overCapacityCount == 0 else {
            throw Abort(.internalServerError, reason: "Existing classes exceed their configured capacity; reconcile enrollment data before applying this migration.")
        }

        // Catalog lookup followed by conditional DDL is safe to retry.
        let constraintRow = try await sql.raw("""
            SELECT COUNT(*) AS count
            FROM pg_constraint
            WHERE conname = 'classes_capacity_range'
              AND conrelid = 'classes'::regclass
            """).first()
        let constraintCount = try constraintRow?.decode(column: "count", as: Int64.self) ?? 0
        if constraintCount == 0 {
            try await sql.raw("""
                ALTER TABLE classes
                ADD CONSTRAINT classes_capacity_range
                CHECK (capacity BETWEEN 1 AND 500)
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_capacity_range;").run()
    }
}

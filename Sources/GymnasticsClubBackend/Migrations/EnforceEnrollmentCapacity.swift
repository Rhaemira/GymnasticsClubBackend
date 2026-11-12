import Fluent
import Vapor
import SQLKit

/// PostgreSQL row locking serializes all enrollments for a given class and
/// database constraints protect the capacity invariant from non-HTTP writers.
struct EnforceEnrollmentCapacity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Enrollment capacity migration requires PostgreSQL.")
        }

        // Fail safely when historical rows violate the invariant. Never delete
        // enrollments or silently rewrite a class's configured capacity.
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

        try await sql.raw("""
            CREATE OR REPLACE FUNCTION gymnastics_check_class_capacity()
            RETURNS trigger AS $$
            DECLARE
                class_capacity integer;
                enrollment_count integer;
            BEGIN
                IF TG_TABLE_NAME = 'classes' THEN
                    SELECT COUNT(*) INTO enrollment_count
                    FROM enrollments WHERE class_id = OLD.id;
                    IF NEW.capacity < enrollment_count THEN
                        RAISE EXCEPTION 'class_capacity_below_enrollment'
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END IF;

                SELECT capacity INTO class_capacity
                FROM classes WHERE id = NEW.class_id FOR UPDATE;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'class_not_found' USING ERRCODE = '23503';
                END IF;

                SELECT COUNT(*) INTO enrollment_count
                FROM enrollments WHERE class_id = NEW.class_id;
                IF enrollment_count >= class_capacity THEN
                    RAISE EXCEPTION 'class_capacity_exceeded'
                        USING ERRCODE = '23514';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
            """).run()

        try await sql.raw("""
            CREATE TRIGGER gymnastics_enrollment_capacity
            BEFORE INSERT ON enrollments
            FOR EACH ROW EXECUTE FUNCTION gymnastics_check_class_capacity();
            """).run()

        try await sql.raw("""
            CREATE TRIGGER gymnastics_class_capacity_update
            BEFORE UPDATE OF capacity ON classes
            FOR EACH ROW EXECUTE FUNCTION gymnastics_check_class_capacity();
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        try await sql.raw("DROP TRIGGER IF EXISTS gymnastics_enrollment_capacity ON enrollments;").run()
        try await sql.raw("DROP TRIGGER IF EXISTS gymnastics_class_capacity_update ON classes;").run()
        try await sql.raw("DROP FUNCTION IF EXISTS gymnastics_check_class_capacity();").run()
        try await sql.raw("ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_capacity_range;").run()
    }
}

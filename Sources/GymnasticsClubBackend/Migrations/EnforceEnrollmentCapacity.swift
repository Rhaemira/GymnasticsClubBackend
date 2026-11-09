import Fluent
import SQLKit

/// PostgreSQL row locking serializes all enrollments for a given class.
struct EnforceEnrollmentCapacity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Enrollment capacity migration requires PostgreSQL.")
        }
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
    }
}

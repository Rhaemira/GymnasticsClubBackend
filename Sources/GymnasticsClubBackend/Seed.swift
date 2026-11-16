import Fluent
import Vapor

/// Idempotent development seed command. Existing matching records are reused,
/// and existing enrollments are never duplicated.
struct SeedData: AsyncCommand {
    struct Signature: CommandSignature {}

    var help: String {
        "Populate the development database with sample gymnastics data."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let db = context.application.db

        let coach: Coach
        if let existing = try await Coach.query(on: db)
            .filter(\.$fullName == "Sara Ahmadi")
            .first() {
            coach = existing
        } else {
            let created = Coach(fullName: "Sara Ahmadi", specialty: "Artistic Gymnastics")
            try await created.save(on: db)
            coach = created
        }

        let athlete1 = try await athlete(named: "Amirali", age: 21, level: "Advanced", on: db)
        let athlete2 = try await athlete(named: "Reza", age: 18, level: "Beginner", on: db)

        let gymClass: Class
        if let existing = try await Class.query(on: db)
            .filter(\.$name == "Advanced Floor")
            .first() {
            gymClass = existing
        } else {
            let created = Class(
                name: "Advanced Floor",
                capacity: 15,
                coachID: try coach.requireID()
            )
            try await created.save(on: db)
            gymClass = created
        }

        try await ensureEnrollment(for: athlete1, in: gymClass, on: db)
        try await ensureEnrollment(for: athlete2, in: gymClass, on: db)

        context.console.print("Seed data is ready.")
    }

    private func athlete(named name: String, age: Int, level: String, on db: any Database) async throws -> Athlete {
        if let existing = try await Athlete.query(on: db)
            .filter(\.$fullName == name)
            .first() {
            return existing
        }
        let created = Athlete(fullName: name, age: age, level: level)
        try await created.save(on: db)
        return created
    }

    private func ensureEnrollment(for athlete: Athlete, in gymClass: Class, on db: any Database) async throws {
        let athleteID = try athlete.requireID()
        let classID = try gymClass.requireID()
        let existing = try await Enrollment.query(on: db)
            .filter(\.$athlete.$id == athleteID)
            .filter(\.$gymClass.$id == classID)
            .first()
        guard existing == nil else { return }
        try await Enrollment(athleteID: athleteID, classID: classID).save(on: db)
    }
}

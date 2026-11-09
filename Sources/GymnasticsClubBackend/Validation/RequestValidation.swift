import Vapor

enum RequestValidation {
    static func name(_ value: String, field: String, maximum: Int = 100) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...maximum).contains(cleaned.count) else {
            throw Abort(.badRequest, reason: "\(field) must contain between 2 and \(maximum) non-whitespace characters.")
        }
        return cleaned
    }

    static func athlete(_ input: WriteAthleteDTO) throws {
        _ = try name(input.fullName, field: "Athlete name")
        guard (1...120).contains(input.age) else {
            throw Abort(.badRequest, reason: "Athlete age must be between 1 and 120.")
        }
        let allowed = ["beginner", "intermediate", "advanced", "elite"]
        guard allowed.contains(input.level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw Abort(.badRequest, reason: "Athlete level must be Beginner, Intermediate, Advanced, or Elite.")
        }
    }

    static func coach(_ input: WriteCoachDTO) throws {
        _ = try name(input.fullName, field: "Coach name")
        _ = try name(input.specialty, field: "Coach specialty")
    }

    static func gymClass(_ input: CreateClassDTO) throws {
        _ = try name(input.name, field: "Class name")
        guard (1...500).contains(input.capacity) else {
            throw Abort(.badRequest, reason: "Class capacity must be between 1 and 500.")
        }
    }

    static func attendance(_ input: CreateAttendanceDTO) throws {
        guard input.attendedOn <= Date().addingTimeInterval(300) else {
            throw Abort(.badRequest, reason: "Attendance date cannot be in the future.")
        }
    }
}

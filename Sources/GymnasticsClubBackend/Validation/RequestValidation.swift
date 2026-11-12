import Vapor

enum RequestValidation {
    static func name(_ value: String, field: String, maximum: Int = 100) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...maximum).contains(cleaned.count) else {
            throw Abort(.badRequest, reason: "\(field) must contain between 2 and \(maximum) non-whitespace characters.")
        }
        return cleaned
    }

    static func login(_ input: LoginRequest) throws -> String {
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.utf8.count <= 254,
              parts.count == 2,
              !parts[0].isEmpty,
              parts[0].utf8.count <= 64,
              !parts[1].isEmpty,
              !email.contains(where: \.isWhitespace),
              !email.contains(where: { "<>()[],:;\\"".contains($0) }) else {
            throw Abort(.badRequest, reason: "Enter a valid email address.")
        }

        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty &&
                  label.utf8.count <= 63 &&
                  label.first != "-" &&
                  label.last != "-" &&
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
              }) else {
            throw Abort(.badRequest, reason: "Enter a valid email address.")
        }

        guard !input.password.isEmpty, input.password.utf8.count <= 72 else {
            throw Abort(.badRequest, reason: "Password must contain between 1 and 72 UTF-8 bytes.")
        }
        return email
    }

    static func administrator(email rawEmail: String, password: String) throws -> String {
        let email = try login(LoginRequest(email: rawEmail, password: password))
        guard password.count >= 12 else {
            throw Abort(.badRequest, reason: "Administrator passwords must contain at least 12 characters.")
        }
        return email
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

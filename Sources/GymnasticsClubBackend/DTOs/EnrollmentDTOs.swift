import Vapor

struct CreateEnrollmentDTO: Content {
    let athleteID: UUID
    let classID: UUID

    enum CodingKeys: String, CodingKey {
        case athleteID = "athlete_id"
        case classID = "class_id"
    }
}

struct EnrollmentResponse: Content {
    let id: UUID?
    let athlete: AthleteAttendanceResponse
    let gymClass: ClassAttendanceResponse
}

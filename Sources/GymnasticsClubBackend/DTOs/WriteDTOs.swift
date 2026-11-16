import Vapor

struct WriteAthleteDTO: Content {
    let fullName: String
    let age: Int
    let level: String
}
struct WriteCoachDTO: Content {
    let fullName: String
    let specialty: String
}

//
//  Enrollment.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent
import Vapor

final class Enrollment: Model, Content, @unchecked Sendable {

    static let schema = "enrollments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "athlete_id")
    var athlete: Athlete

    @Parent(key: "class_id")
    var gymClass: Class

    init() {}

    init(
        id: UUID? = nil,
        athleteID: UUID,
        classID: UUID
    ) {
        self.id = id

        self.$athlete.id = athleteID

        self.$gymClass.id = classID
    }
}
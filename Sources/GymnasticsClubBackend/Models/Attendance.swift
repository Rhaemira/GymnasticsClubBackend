//
//  Attendance.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent
import Vapor

final class Attendance:
Model,
Content,
@unchecked Sendable {

    static let schema =
    "attendance"

    @ID(key: .id)
    var id: UUID?

    @Parent(
        key:
        "athlete_id"
    )
    var athlete:
    Athlete

    @Parent(
        key:
        "class_id"
    )
    var gymClass:
    Class

    @Field(
        key:
        "attended_on"
    )
    var attendedOn:
    Date

    init() {}

    init(
        id: UUID? = nil,
        athleteID: UUID,
        classID: UUID,
        attendedOn: Date
    ) {

        self.id =
        id

        self.$athlete.id =
        athleteID

        self.$gymClass.id =
        classID

        self.attendedOn =
        attendedOn
    }
}
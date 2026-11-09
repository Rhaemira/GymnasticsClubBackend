//
//  Class.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent
import Vapor

final class Class: Model, Content, @unchecked Sendable {

    static let schema = "classes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "capacity")
    var capacity: Int

    @Parent(key: "coach_id")
    var coach: Coach

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        capacity: Int,
        coachID: UUID
    ) {
        self.id = id
        self.name = name
        self.capacity = capacity
        self.$coach.id = coachID
    }
}
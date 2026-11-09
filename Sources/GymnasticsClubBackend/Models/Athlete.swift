//
//  Athlete.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent
import Vapor

final class Athlete: Model, Content, @unchecked Sendable {

    static let schema = "athletes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "full_name")
    var fullName: String

    @Field(key: "age")
    var age: Int

    @Field(key: "level")
    var level: String

    init() {}

    init(
        id: UUID? = nil,
        fullName: String,
        age: Int,
        level: String
    ) {
        self.id = id
        self.fullName = fullName
        self.age = age
        self.level = level
    }
}
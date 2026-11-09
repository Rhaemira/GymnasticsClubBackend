//
//  File.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/13/26.
//

import Fluent
import Vapor

final class Coach: Model, Content, @unchecked Sendable {

    static let schema = "coaches"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "full_name")
    var fullName: String

    @Field(key: "specialty")
    var specialty: String
    
    @Children(for: \.$coach)
    var classes: [Class]

    init() {}

    init(
        id: UUID? = nil,
        fullName: String,
        specialty: String
    ) {
        self.id = id
        self.fullName = fullName
        self.specialty = specialty
    }
}

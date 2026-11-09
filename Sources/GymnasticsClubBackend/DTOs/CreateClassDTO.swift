//
//  CreateClassDTO.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/14/26.
//


import Vapor

struct CreateClassDTO: Content {

    let name: String

    let capacity: Int

    let coachID: UUID

    enum CodingKeys: String, CodingKey {

        case name
        case capacity
        case coachID = "coach_id"

    }

}

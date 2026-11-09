//
//  ClassResponse.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/14/26.
//


import Vapor

struct ClassResponse: Content {

    let id: UUID?
    let name: String
    let capacity: Int
    let coach: CoachResponse

}

struct CoachResponse: Content {

    let id: UUID?
    let fullName: String

}
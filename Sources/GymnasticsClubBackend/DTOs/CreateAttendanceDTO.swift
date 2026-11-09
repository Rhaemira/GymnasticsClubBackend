//
//  CreateAttendanceDTO.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/15/26.
//


import Vapor

struct CreateAttendanceDTO: Content {

    let athleteID: UUID

    let classID: UUID

    let attendedOn: Date

}
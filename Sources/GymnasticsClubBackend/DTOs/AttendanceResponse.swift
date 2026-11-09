//
//  AttendanceResponse.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/15/26.
//


import Vapor

struct AttendanceResponse: Content {

    let id: UUID?

    let athlete: AthleteAttendanceResponse

    let gymClass: ClassAttendanceResponse

    let attendedOn: Date

}

struct AthleteAttendanceResponse: Content {

    let id: UUID?

    let fullName: String

}

struct ClassAttendanceResponse: Content {

    let id: UUID?

    let name: String

}
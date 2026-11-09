//
//  ReportsResponse.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Vapor

struct ReportsResponse: Content {
    let totalAthletes: Int
    let totalCoaches: Int
    let totalClasses: Int
    let totalEnrollments: Int
    let totalAttendanceRecords: Int
}
//
//  AnalyticsResponse.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/18/26.
//


import Vapor

struct AnalyticsResponse: Content {

    let overview: OverviewResponse

    let athleteLevels: [LevelResponse]

    let coachWorkload: [CoachWorkloadResponse]

    let classUtilization: [ClassUtilizationResponse]

}

struct OverviewResponse: Content {

    let athletes: Int
    let coaches: Int
    let classes: Int
    let enrollments: Int
    let attendance: Int

}

struct LevelResponse: Content {

    let level: String
    let count: Int

}

struct CoachWorkloadResponse: Content {

    let coach: String
    let classes: Int

}

struct ClassUtilizationResponse: Content {

    let className: String
    let enrolled: Int
    let capacity: Int

}
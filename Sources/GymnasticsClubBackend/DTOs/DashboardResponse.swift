//
//  DashboardResponse.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Vapor

struct DashboardResponse:
Content {

    let coach: String

    let classes:
    [ClassSummary]
}

struct ClassSummary:
Content {

    let name:
    String

    let capacity:
    Int
}
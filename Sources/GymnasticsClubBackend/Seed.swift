//
//  SeedData.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//

import Fluent
import Vapor

struct SeedData: Command {
    
    struct Signature: CommandSignature {}
    
    var help: String {
        "Populate database with sample data"
    }
    
    func run(
        using context: CommandContext,
        signature: Signature
    ) throws {
        let promise = context.application.eventLoopGroup.next().makePromise(of: Void.self)
        promise.completeWithTask {
            let db = context.application.db
            
            let coach = Coach(
                fullName: "Sara Ahmadi",
                specialty: "Artistic Gymnastics"
            )
            try await coach.save(on: db)
            
            let athlete1 = Athlete(
                fullName: "Amirali",
                age: 21,
                level: "Advanced"
            )
            let athlete2 = Athlete(
                fullName: "Reza",
                age: 18,
                level: "Beginner"
            )
            try await athlete1.save(on: db)
            try await athlete2.save(on: db)
            
            let gymClass = Class(
                name: "Advanced Floor",
                capacity: 15,
                coachID: try coach.requireID()
            )
            try await gymClass.save(on: db)
            
            let enrollment1 = Enrollment(
                athleteID: try athlete1.requireID(),
                classID: try gymClass.requireID()
            )
            let enrollment2 = Enrollment(
                athleteID: try athlete2.requireID(),
                classID: try gymClass.requireID()
            )
            try await enrollment1.save(on: db)
            try await enrollment2.save(on: db)
            
            context.console.print("Seed complete ✅")
        }
        try promise.futureResult.wait()
    }
}

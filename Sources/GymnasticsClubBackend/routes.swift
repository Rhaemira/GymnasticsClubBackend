import Fluent
import Vapor

func routes(_ app: Application) throws {

    app.get {_ in 
        "Gymnastics Club API"
    }

    // Coaches

    app.get("coaches") { req async throws -> [Coach] in
        try await Coach.query(on: req.db).all()
    }

    app.post("coaches") { req async throws -> Coach in
        let coach = try req.content.decode(Coach.self)

        try await coach.save(on: req.db)

        return coach
    }
    
    app.put("coaches", ":coachID") { req async throws -> Coach in

        guard let coach =
            try await Coach.find(
                req.parameters.get("coachID"),
                on: req.db
            )
        else {
            throw Abort(.notFound)
        }

        let update =
            try req.content.decode(
                Coach.self
            )

        coach.fullName =
            update.fullName

        coach.specialty =
            update.specialty

        try await coach.save(
            on: req.db
        )

        return coach
    }
    
    app.delete("coaches", ":coachID") { req async throws -> HTTPStatus in

        guard let coachID = req.parameters.get("coachID", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        // Find every class owned by this coach
        let classes = try await Class.query(on: req.db)
            .filter(\.$coach.$id == coachID)
            .all()

        // Delete enrollments, then each class
        for gymClass in classes {

            guard let classID = gymClass.id else { continue }

            try await Enrollment.query(on: req.db)
                .filter(\.$gymClass.$id == classID)
                .delete()

            try await gymClass.delete(on: req.db)
        }

        // Finally delete the coach
        guard let coach = try await Coach.find(coachID, on: req.db) else {
            throw Abort(.notFound)
        }

        try await coach.delete(on: req.db)

        return .ok
    }
    // Athletes

    app.get("athletes") { req async throws -> [Athlete] in
        try await Athlete.query(on: req.db).all()
    }

    app.post("athletes") { req async throws -> Athlete in

        let athlete = try req.content.decode(Athlete.self)

        try await athlete.save(on: req.db)

        return athlete
    }
    
    // Classes
    
    app.get("classes") { req async throws -> [ClassResponse] in

        let classes = try await Class.query(on: req.db)
            .with(\.$coach)
            .all()

        return classes.map { gymClass in

            ClassResponse(

                id: gymClass.id,

                name: gymClass.name,

                capacity: gymClass.capacity,

                coach: CoachResponse(

                    id: gymClass.coach.id,

                    fullName: gymClass.coach.fullName

                )

            )

        }

    }

    app.post("classes") { req async throws -> Class in

        let input = try req.content.decode(CreateClassDTO.self)

        let gymClass = Class(

            name: input.name,

            capacity: input.capacity,

            coachID: input.coachID

        )

        try await gymClass.save(on: req.db)

        return gymClass
        
    }
    
    app.put("classes", ":classID") { req async throws -> ClassResponse in

        guard let gymClass = try await Class.find(
            req.parameters.get("classID"),
            on: req.db
        ) else {

            throw Abort(.notFound)

        }

        let input = try req.content.decode(CreateClassDTO.self)

        gymClass.name = input.name
        gymClass.capacity = input.capacity
        gymClass.$coach.id = input.coachID

        try await gymClass.save(on: req.db)

        try await gymClass.$coach.load(on: req.db)

        return ClassResponse(

            id: gymClass.id,

            name: gymClass.name,

            capacity: gymClass.capacity,

            coach: CoachResponse(

                id: gymClass.coach.id,

                fullName: gymClass.coach.fullName

            )

        )

    }
    
    app.delete("classes", ":classID") { req async throws -> HTTPStatus in

        guard let classID = req.parameters.get("classID", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        try await Enrollment.query(on: req.db)
            .filter(\.$gymClass.$id == classID)
            .delete()

        guard let gymClass = try await Class.find(classID, on: req.db) else {
            throw Abort(.notFound)
        }

        try await gymClass.delete(on: req.db)

        return .ok
    }
    
    // Enrollments
    
    app.get("enrollments") { req async throws -> [Enrollment] in
        try await Enrollment.query(on: req.db).all()
    }

    app.post("enrollments") { req async throws -> Enrollment in

        let enrollment =
            try req.content.decode(
                Enrollment.self
            )

        try await enrollment
            .save(on: req.db)

        return enrollment
    }
    
    // Dashboard
    
    app.get("dashboard") {req async throws-> [DashboardResponse] in

        let coaches =
            try await Coach.query(on:req.db)
    .with(
    \.$classes
    )
    .all()

    return coaches
    .map {

    coach in

    DashboardResponse(

    coach:
    coach.fullName,

    classes:
    coach.classes
    .map {

    ClassSummary(

    name:
    $0.name,

    capacity:
    $0.capacity
    )

    }
    )

    }
    }
    
    // MARK: - Attendance

    app.get("attendance") { req async throws -> [AttendanceResponse] in

        let records = try await Attendance.query(on: req.db)
            .with(\.$athlete)
            .with(\.$gymClass)
            .all()

        return records.map { record in

            AttendanceResponse(

                id: record.id,

                athlete: AthleteAttendanceResponse(

                    id: record.athlete.id,

                    fullName: record.athlete.fullName

                ),

                gymClass: ClassAttendanceResponse(

                    id: record.gymClass.id,

                    name: record.gymClass.name

                ),

                attendedOn: record.attendedOn

            )

        }

    }

    app.post("attendance") { req async throws -> AttendanceResponse in

        let input = try req.content.decode(CreateAttendanceDTO.self)

        let attendance = Attendance(

            athleteID: input.athleteID,

            classID: input.classID,

            attendedOn: input.attendedOn

        )

        try await attendance.save(on: req.db)

        try await attendance.$athlete.load(on: req.db)

        try await attendance.$gymClass.load(on: req.db)

        return AttendanceResponse(

            id: attendance.id,

            athlete: AthleteAttendanceResponse(

                id: attendance.athlete.id,

                fullName: attendance.athlete.fullName

            ),

            gymClass: ClassAttendanceResponse(

                id: attendance.gymClass.id,

                name: attendance.gymClass.name

            ),

            attendedOn: attendance.attendedOn

        )

    }
    
    app.put("attendance", ":attendanceID") { req async throws -> AttendanceResponse in

        guard let attendance = try await Attendance.find(
            req.parameters.get("attendanceID"),
            on: req.db
        ) else {

            throw Abort(.notFound)

        }

        let input = try req.content.decode(CreateAttendanceDTO.self)

        attendance.$athlete.id = input.athleteID
        attendance.$gymClass.id = input.classID
        attendance.attendedOn = input.attendedOn

        try await attendance.save(on: req.db)

        try await attendance.$athlete.load(on: req.db)
        try await attendance.$gymClass.load(on: req.db)

        return AttendanceResponse(

            id: attendance.id,

            athlete: AthleteAttendanceResponse(

                id: attendance.athlete.id,

                fullName: attendance.athlete.fullName

            ),

            gymClass: ClassAttendanceResponse(

                id: attendance.gymClass.id,

                name: attendance.gymClass.name

            ),

            attendedOn: attendance.attendedOn

        )

    }
    
    app.delete("attendance", ":attendanceID") { req async throws -> HTTPStatus in

        guard let attendance = try await Attendance.find(

            req.parameters.get("attendanceID"),

            on: req.db

        ) else {

            throw Abort(.notFound)

        }

        try await attendance.delete(on: req.db)

        return .ok

    }
    
    // Reports
    
    app.get("reports") { req async throws -> ReportsResponse in

        async let athletes =
            Athlete.query(on: req.db).count()

        async let coaches =
            Coach.query(on: req.db).count()

        async let classes =
            Class.query(on: req.db).count()

        async let enrollments =
            Enrollment.query(on: req.db).count()

        async let attendance =
            Attendance.query(on: req.db).count()

        return ReportsResponse(
            totalAthletes: try await athletes,
            totalCoaches: try await coaches,
            totalClasses: try await classes,
            totalEnrollments: try await enrollments,
            totalAttendanceRecords: try await attendance
        )
    }
    
    app.get("analytics") { req async throws -> AnalyticsResponse in

        async let athleteCount =
            Athlete.query(on: req.db).count()

        async let coachCount =
            Coach.query(on: req.db).count()

        async let classCount =
            Class.query(on: req.db).count()

        async let enrollmentCount =
            Enrollment.query(on: req.db).count()

        async let attendanceCount =
            Attendance.query(on: req.db).count()

        let athletes =
            try await Athlete.query(on: req.db).all()

        let coaches =
            try await Coach.query(on: req.db)
                .with(\.$classes)
                .all()

        let classes =
            try await Class.query(on: req.db)
                .all()
        let athleteLevels =

            Dictionary(

                grouping: athletes,

                by: \.level

            )

            .map {

                LevelResponse(

                    level: $0.key,

                    count: $0.value.count

                )

            }
        
        let coachWorkload =

            coaches.map {

                CoachWorkloadResponse(

                    coach: $0.fullName,

                    classes: $0.classes.count

                )

            }
        
        var utilization: [ClassUtilizationResponse] = []

        for gymClass in classes {

            guard let classID = gymClass.id else {

                continue

            }

            let enrolled =

                try await Enrollment.query(on: req.db)

                    .filter(\.$gymClass.$id == classID)

                    .count()

            utilization.append(

                ClassUtilizationResponse(

                    className: gymClass.name,

                    enrolled: enrolled,

                    capacity: gymClass.capacity

                )

            )

        }
        
        return AnalyticsResponse(

            overview:

                OverviewResponse(

                    athletes: try await athleteCount,

                    coaches: try await coachCount,

                    classes: try await classCount,

                    enrollments: try await enrollmentCount,

                    attendance: try await attendanceCount

                ),

            athleteLevels: athleteLevels,

            coachWorkload: coachWorkload,

            classUtilization: utilization

        )

    }
    
    // Athelete UPDATE
    
    app.put("athletes", ":athleteID") { req async throws -> Athlete in

        guard let athlete =
            try await Athlete.find(
                req.parameters.get("athleteID"),
                on: req.db
            )
        else {
            throw Abort(.notFound)
        }

        let update =
            try req.content.decode(
                Athlete.self
            )

        athlete.fullName =
            update.fullName

        athlete.age =
            update.age

        athlete.level =
            update.level

        try await athlete.save(
            on: req.db
        )

        return athlete
    }
    
    // Athelete DELETE
    
    app.delete("athletes", ":athleteID") { req async throws -> HTTPStatus in

        guard let athleteID =
            req.parameters.get(
                "athleteID",
                as: UUID.self
            )
        else {
            throw Abort(.badRequest)
        }

        try await Enrollment
            .query(on: req.db)
            .filter(
                \.$athlete.$id == athleteID
            )
            .delete()

        try await Attendance
            .query(on: req.db)
            .filter(
                \.$athlete.$id == athleteID
            )
            .delete()

        guard let athlete =
            try await Athlete.find(
                athleteID,
                on: req.db
            )
        else {
            throw Abort(.notFound)
        }

        try await athlete.delete(
            on: req.db
        )

        return .ok
    }

}

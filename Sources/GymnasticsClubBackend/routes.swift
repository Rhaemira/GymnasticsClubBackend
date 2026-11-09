import Fluent
import Vapor

func routes(_ app: Application) throws {
    let protected = app.grouped(AccessTokenAuthenticator(), AdminUser.guardMiddleware())

    app.get {_ in 
        "Gymnastics Club API"
    }
    app.get("health") { req async -> Response in
        do {
            _ = try await Coach.query(on: req.db).count()
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(string: #"{"status":"ok","database":"ready"}"#))
        } catch {
            req.logger.error("Health check database query failed: \\(error.localizedDescription)")
            return Response(status: .serviceUnavailable, headers: ["Content-Type": "application/json"], body: .init(string: #"{"status":"unavailable","database":"unavailable"}"#))
        }
    }

    app.post("auth", "login") { req async throws -> LoginResponse in
        let input = try req.content.decode(LoginRequest.self)
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty, !input.password.isEmpty else { throw Abort(.badRequest, reason: "Email and password are required.") }
        let key = "\\(req.remoteAddress?.ipAddress ?? "unknown"):\\(email)"
        guard await loginRateLimiter.isAllowed(key) else { throw Abort(.tooManyRequests, reason: "Too many login attempts. Try again later.") }
        guard let user = try await AdminUser.query(on: req.db).filter(\\.$email == email).first(),
              try Bcrypt.verify(input.password, created: user.passwordHash) else {
            await loginRateLimiter.recordFailure(key)
            throw Abort(.unauthorized, reason: "Email or password is incorrect.")
        }
        await loginRateLimiter.reset(key)
        let ttl = Int(Environment.get("AUTH_TOKEN_TTL_SECONDS") ?? "43200") ?? 43200
        guard (900...86400).contains(ttl) else { throw Abort(.internalServerError, reason: "AUTH_TOKEN_TTL_SECONDS must be between 900 and 86400.") }
        let rawToken = SecureAccessToken.generate()
        let expiresAt = Date().addingTimeInterval(TimeInterval(ttl))
        try await AccessToken(userID: user.requireID(), tokenHash: SecureAccessToken.digest(rawToken), expiresAt: expiresAt).save(on: req.db)
        return LoginResponse(token: rawToken, expiresAt: expiresAt, user: AdminUserResponse(id: try user.requireID(), email: user.email))
    }

    protected.get("auth", "me") { req async throws -> AdminUserResponse in
        let user = try req.auth.require(AdminUser.self)
        return AdminUserResponse(id: try user.requireID(), email: user.email)
    }

    protected.post("auth", "logout") { req async throws -> HTTPStatus in
        guard let rawToken = req.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        guard let token = try await AccessToken.query(on: req.db).filter(\\.$tokenHash == SecureAccessToken.digest(rawToken)).first() else { return .noContent }
        token.revokedAt = .now
        try await token.save(on: req.db)
        return .noContent
    }


    // Coaches

    protected.get("coaches") { req async throws -> [Coach] in
        try await Coach.query(on: req.db).all()
    }

    protected.post("coaches") { req async throws -> Coach in
        let coach = try req.content.decode(Coach.self)

        try await coach.save(on: req.db)

        return coach
    }
    
    protected.put("coaches", ":coachID") { req async throws -> Coach in

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
    
    protected.delete("coaches", ":coachID") { req async throws -> HTTPStatus in

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

    protected.get("athletes") { req async throws -> [Athlete] in
        try await Athlete.query(on: req.db).all()
    }

    protected.post("athletes") { req async throws -> Athlete in

        let athlete = try req.content.decode(Athlete.self)

        try await athlete.save(on: req.db)

        return athlete
    }
    
    // Classes
    
    protected.get("classes") { req async throws -> [ClassResponse] in

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

    protected.post("classes") { req async throws -> Class in

        let input = try req.content.decode(CreateClassDTO.self)

        let gymClass = Class(

            name: input.name,

            capacity: input.capacity,

            coachID: input.coachID

        )

        try await gymClass.save(on: req.db)

        return gymClass
        
    }
    
    protected.put("classes", ":classID") { req async throws -> ClassResponse in

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
    
    protected.delete("classes", ":classID") { req async throws -> HTTPStatus in

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
    
    protected.get("enrollments") { req async throws -> [Enrollment] in
        try await Enrollment.query(on: req.db).all()
    }

    protected.post("enrollments") { req async throws -> Enrollment in

        let enrollment =
            try req.content.decode(
                Enrollment.self
            )

        try await enrollment
            .save(on: req.db)

        return enrollment
    }
    
    // Dashboard
    
    protected.get("dashboard") {req async throws-> [DashboardResponse] in

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

    protected.get("attendance") { req async throws -> [AttendanceResponse] in

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

    protected.post("attendance") { req async throws -> AttendanceResponse in

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
    
    protected.put("attendance", ":attendanceID") { req async throws -> AttendanceResponse in

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
    
    protected.delete("attendance", ":attendanceID") { req async throws -> HTTPStatus in

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
    
    protected.get("reports") { req async throws -> ReportsResponse in

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
    
    protected.get("analytics") { req async throws -> AnalyticsResponse in

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
    
    protected.put("athletes", ":athleteID") { req async throws -> Athlete in

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
    
    protected.delete("athletes", ":athleteID") { req async throws -> HTTPStatus in

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

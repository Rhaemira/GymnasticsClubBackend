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
            req.logger.error("Health check database query failed.")
            return Response(status: .serviceUnavailable, headers: ["Content-Type": "application/json"], body: .init(string: #"{"status":"unavailable","database":"unavailable"}"#))
        }
    }

    app.post("auth", "login") { req async throws -> LoginResponse in
        let input = try req.content.decode(LoginRequest.self)
        let email = try RequestValidation.login(input)
        guard let loginRateLimiter = req.application.storage[LoginRateLimiterKey.self] else {
            throw Abort(.internalServerError, reason: "Login protection is unavailable.")
        }
        let ipKey = "ip:\(req.remoteAddress?.ipAddress ?? "unknown")"
        let accountKey = "account:\(email)"
        guard await loginRateLimiter.isAllowed(ipKey), await loginRateLimiter.isAllowed(accountKey) else {
            throw Abort(.tooManyRequests, reason: "Too many login attempts. Try again later.")
        }

        // Perform a bcrypt operation even when the account does not exist so
        // unknown emails do not get a cheap, easily distinguishable response.
        let user = try await AdminUser.query(on: req.db).filter(\.$email == email).first()
        let passwordMatches: Bool
        if let user {
            passwordMatches = try Bcrypt.verify(input.password, created: user.passwordHash)
        } else {
            _ = try Bcrypt.hash(input.password)
            passwordMatches = false
        }

        guard let user, passwordMatches else {
            await loginRateLimiter.recordFailure(ipKey)
            await loginRateLimiter.recordFailure(accountKey)
            throw Abort(.unauthorized, reason: "Email or password is incorrect.")
        }

        // A successful login resets only that account's failures. It must not
        // erase failures accumulated by other accounts from the same source IP.
        await loginRateLimiter.reset(accountKey)
        let ttl = Int(Environment.get("AUTH_TOKEN_TTL_SECONDS") ?? "43200") ?? 43200
        guard (900...86400).contains(ttl) else { throw Abort(.internalServerError, reason: "AUTH_TOKEN_TTL_SECONDS must be between 900 and 86400.") }
        let now = Date()
        // Tokens are opaque and expire within 24 hours. Opportunistically
        // remove expired digests during login so the session table stays bounded.
        try await AccessToken.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$expiresAt <= now)
                group.filter(\.$revokedAt != nil)
            }
            .delete()

        let rawToken = SecureAccessToken.generate()
        let expiresAt = now.addingTimeInterval(TimeInterval(ttl))
        try await AccessToken(userID: user.requireID(), tokenHash: SecureAccessToken.digest(rawToken), expiresAt: expiresAt).save(on: req.db)
        return LoginResponse(token: rawToken, expiresAt: expiresAt, user: AdminUserResponse(id: try user.requireID(), email: user.email))
    }

    protected.get("auth", "me") { req async throws -> AdminUserResponse in
        let user = try req.auth.require(AdminUser.self)
        return AdminUserResponse(id: try user.requireID(), email: user.email)
    }

    protected.post("auth", "logout") { req async throws -> HTTPStatus in
        guard let rawToken = req.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        guard let token = try await AccessToken.query(on: req.db).filter(\.$tokenHash == SecureAccessToken.digest(rawToken)).first() else { return .noContent }
        token.revokedAt = .now
        try await token.save(on: req.db)
        return .noContent
    }


    // Coaches

    protected.get("coaches") { req async throws -> [Coach] in
        try await Coach.query(on: req.db).all()
    }

    protected.post("coaches") { req async throws -> Coach in
        let input = try req.content.decode(WriteCoachDTO.self)
        try RequestValidation.coach(input)
        let coach = Coach(
            fullName: try RequestValidation.name(input.fullName, field: "Coach name"),
            specialty: try RequestValidation.name(input.specialty, field: "Coach specialty")
        )
        do {
            try await coach.save(on: req.db)
        } catch {
            if isPostgreSQLUniqueViolation(error) {
                throw Abort(.conflict, reason: "A coach with this name already exists.")
            }
            throw error
        }
        return coach
    }
    
    protected.put("coaches", ":coachID") { req async throws -> Coach in

        guard let coachID = req.parameters.get("coachID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid coach identifier.")
        }
        guard let coach = try await Coach.find(coachID, on: req.db) else {
            throw Abort(.notFound)
        }

        let update = try req.content.decode(WriteCoachDTO.self)
        try RequestValidation.coach(update)
        coach.fullName = try RequestValidation.name(update.fullName, field: "Coach name")
        coach.specialty = try RequestValidation.name(update.specialty, field: "Coach specialty")

        do {
            try await coach.save(on: req.db)
        } catch {
            if isPostgreSQLUniqueViolation(error) {
                throw Abort(.conflict, reason: "A coach with this name already exists.")
            }
            throw error
        }

        return coach
    }
    
        protected.delete("coaches", ":coachID") { req async throws -> HTTPStatus in
        guard let coachID = req.parameters.get("coachID", as: UUID.self) else { throw Abort(.badRequest, reason: "Invalid coach identifier.") }
        try await req.db.transaction { database in
            guard let coach = try await Coach.find(coachID, on: database) else { throw Abort(.notFound, reason: "Coach was not found.") }
            let classes = try await Class.query(on: database).filter(\.$coach.$id == coachID).all()
            for gymClass in classes {
                guard let classID = gymClass.id else { continue }
                try await Attendance.query(on: database).filter(\.$gymClass.$id == classID).delete()
                try await Enrollment.query(on: database).filter(\.$gymClass.$id == classID).delete()
                try await gymClass.delete(on: database)
            }
            try await coach.delete(on: database)
        }
        return .ok
    }

    // Athletes

    protected.get("athletes") { req async throws -> [Athlete] in
        try await Athlete.query(on: req.db).all()
    }

    protected.post("athletes") { req async throws -> Athlete in

        let input = try req.content.decode(WriteAthleteDTO.self)
        try RequestValidation.athlete(input)
        let athlete = Athlete(
            fullName: try RequestValidation.name(input.fullName, field: "Athlete name"),
            age: input.age,
            level: try RequestValidation.athleteLevel(input.level)
        )
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
        try RequestValidation.gymClass(input)
        guard try await Coach.find(input.coachID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Coach was not found.")
        }

        let gymClass = Class(

            name: try RequestValidation.name(input.name, field: "Class name"),

            capacity: input.capacity,

            coachID: input.coachID

        )

        try await gymClass.save(on: req.db)

        return gymClass
        
    }
    
    protected.put("classes", ":classID") { req async throws -> ClassResponse in

        guard let classID = req.parameters.get("classID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid class identifier.")
        }
        guard let gymClass = try await Class.find(classID, on: req.db) else {

            throw Abort(.notFound)

        }

        let input = try req.content.decode(CreateClassDTO.self)
        try RequestValidation.gymClass(input)
        guard try await Coach.find(input.coachID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Coach was not found.")
        }

        gymClass.name = try RequestValidation.name(input.name, field: "Class name")
        gymClass.capacity = input.capacity
        gymClass.$coach.id = input.coachID

        do {
            try await gymClass.save(on: req.db)
        } catch {
            // Use reflection so the PostgreSQL driver's structured serverInfo
            // (constraint message and SQLSTATE) is included in the diagnostic.
            let detail = String(reflecting: error).lowercased()
            if detail.contains("class_capacity_below_enrollment") ||
                detail.contains("class_capacity_exceeded") ||
                detail.contains("23514") {
                throw Abort(.conflict, reason: "Class capacity cannot be lower than its current enrollment.")
            }
            throw error
        }

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
        guard let classID = req.parameters.get("classID", as: UUID.self) else { throw Abort(.badRequest, reason: "Invalid class identifier.") }
        try await req.db.transaction { database in
            guard let gymClass = try await Class.find(classID, on: database) else { throw Abort(.notFound, reason: "Class was not found.") }
            try await Attendance.query(on: database).filter(\.$gymClass.$id == classID).delete()
            try await Enrollment.query(on: database).filter(\.$gymClass.$id == classID).delete()
            try await gymClass.delete(on: database)
        }
        return .ok
    }

    // Enrollments
    
    protected.get("enrollments") { req async throws -> [EnrollmentResponse] in
        let records = try await Enrollment.query(on: req.db)
            .with(\.$athlete)
            .with(\.$gymClass)
            .all()
        return records.map {
            EnrollmentResponse(
                id: $0.id,
                athlete: AthleteAttendanceResponse(id: $0.athlete.id, fullName: $0.athlete.fullName),
                gymClass: ClassAttendanceResponse(id: $0.gymClass.id, name: $0.gymClass.name)
            )
        }
    }

    protected.post("enrollments") { req async throws -> EnrollmentResponse in
        let input = try req.content.decode(CreateEnrollmentDTO.self)
        guard try await Athlete.find(input.athleteID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Athlete was not found.")
        }
        guard try await Class.find(input.classID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Class was not found.")
        }
        let enrollment = Enrollment(athleteID: input.athleteID, classID: input.classID)
        do {
            try await enrollment.save(on: req.db)
        } catch {
            let message = String(reflecting: error).lowercased()
            if message.contains("unique") || message.contains("duplicate") || message.contains("23505") {
                throw Abort(.conflict, reason: "This athlete is already enrolled in the class.")
            }
            if message.contains("capacity") || message.contains("23514") || message.contains("class_capacity_exceeded") {
                throw Abort(.conflict, reason: "This class has reached its capacity.")
            }
            throw error
        }
        try await enrollment.$athlete.load(on: req.db)
        try await enrollment.$gymClass.load(on: req.db)
        return EnrollmentResponse(
            id: enrollment.id,
            athlete: AthleteAttendanceResponse(id: enrollment.athlete.id, fullName: enrollment.athlete.fullName),
            gymClass: ClassAttendanceResponse(id: enrollment.gymClass.id, name: enrollment.gymClass.name)
        )
    }

    protected.delete("enrollments", ":enrollmentID") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("enrollmentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid enrollment identifier.")
        }
        guard let enrollment = try await Enrollment.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Enrollment was not found.")
        }
        try await enrollment.delete(on: req.db)
        return .ok
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
        try RequestValidation.attendance(input)
        guard try await Athlete.find(input.athleteID, on: req.db) != nil else { throw Abort(.notFound, reason: "Athlete was not found.") }
        guard try await Class.find(input.classID, on: req.db) != nil else { throw Abort(.notFound, reason: "Class was not found.") }
        let duplicate = try await Attendance.query(on: req.db)
            .filter(\.$athlete.$id == input.athleteID)
            .filter(\.$gymClass.$id == input.classID)
            .filter(\.$attendedOn == input.attendedOn)
            .first()
        guard duplicate == nil else { throw Abort(.conflict, reason: "An attendance record already exists for this athlete, class and timestamp.") }

        let attendance = Attendance(

            athleteID: input.athleteID,

            classID: input.classID,

            attendedOn: input.attendedOn

        )

        do {
            try await attendance.save(on: req.db)
        } catch {
            if isAttendanceUniquenessViolation(error) {
                throw Abort(.conflict, reason: "An attendance record already exists for this athlete, class and timestamp.")
            }
            throw error
        }

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

        guard let attendanceIDParam = req.parameters.get("attendanceID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid attendance identifier.")
        }
        guard let attendance = try await Attendance.find(attendanceIDParam, on: req.db) else {

            throw Abort(.notFound)

        }

        let input = try req.content.decode(CreateAttendanceDTO.self)
        try RequestValidation.attendance(input)
        guard try await Athlete.find(input.athleteID, on: req.db) != nil else { throw Abort(.notFound, reason: "Athlete was not found.") }
        guard try await Class.find(input.classID, on: req.db) != nil else { throw Abort(.notFound, reason: "Class was not found.") }
        guard let attendanceID = attendance.id else { throw Abort(.internalServerError, reason: "Attendance identifier is missing.") }
        let duplicate = try await Attendance.query(on: req.db)
            .filter(\.$athlete.$id == input.athleteID)
            .filter(\.$gymClass.$id == input.classID)
            .filter(\.$attendedOn == input.attendedOn)
            .filter(\.$id != attendanceID)
            .first()
        guard duplicate == nil else { throw Abort(.conflict, reason: "An attendance record already exists for this athlete, class and timestamp.") }

        attendance.$athlete.id = input.athleteID
        attendance.$gymClass.id = input.classID
        attendance.attendedOn = input.attendedOn

        do {
            try await attendance.save(on: req.db)
        } catch {
            if isAttendanceUniquenessViolation(error) {
                throw Abort(.conflict, reason: "An attendance record already exists for this athlete, class and timestamp.")
            }
            throw error
        }

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

        guard let attendanceID = req.parameters.get("attendanceID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid attendance identifier.")
        }
        guard let attendance = try await Attendance.find(attendanceID, on: req.db) else {

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
        let canonicalLevelOrder = [
            "Beginner": 0,
            "Intermediate": 1,
            "Advanced": 2,
            "Elite": 3
        ]
        let athleteLevels = Dictionary(
            grouping: athletes,
            by: { athlete in
                (try? RequestValidation.athleteLevel(athlete.level))
                    ?? athlete.level.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        .map { LevelResponse(level: $0.key, count: $0.value.count) }
        .sorted { left, right in
            let leftRank = canonicalLevelOrder[left.level] ?? Int.max
            let rightRank = canonicalLevelOrder[right.level] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return left.level.localizedStandardCompare(right.level) == .orderedAscending
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

        guard let athleteID = req.parameters.get("athleteID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid athlete identifier.")
        }
        guard let athlete = try await Athlete.find(athleteID, on: req.db) else {
            throw Abort(.notFound)
        }

        let update = try req.content.decode(WriteAthleteDTO.self)
        try RequestValidation.athlete(update)
        athlete.fullName = try RequestValidation.name(update.fullName, field: "Athlete name")
        athlete.age = update.age
        athlete.level = try RequestValidation.athleteLevel(update.level)

        try await athlete.save(
            on: req.db
        )

        return athlete
    }
    
    // Athelete DELETE
    
        protected.delete("athletes", ":athleteID") { req async throws -> HTTPStatus in
        guard let athleteID = req.parameters.get("athleteID", as: UUID.self) else { throw Abort(.badRequest, reason: "Invalid athlete identifier.") }
        try await req.db.transaction { database in
            guard let athlete = try await Athlete.find(athleteID, on: database) else { throw Abort(.notFound, reason: "Athlete was not found.") }
            try await Enrollment.query(on: database).filter(\.$athlete.$id == athleteID).delete()
            try await Attendance.query(on: database).filter(\.$athlete.$id == athleteID).delete()
            try await athlete.delete(on: database)
        }
        return .ok
    }

}


/// Maps the database's unique index to the same client-facing conflict used by
/// the preflight query. The database constraint remains authoritative under races.
private func isPostgreSQLUniqueViolation(_ error: any Error) -> Bool {
    let details = String(reflecting: error).lowercased()
    return details.contains("23505") || details.contains("unique constraint")
}

private func isAttendanceUniquenessViolation(_ error: any Error) -> Bool {
    let details = String(reflecting: error).lowercased()
    return details.contains("attendance_unique_athlete_class_timestamp") ||
        isPostgreSQLUniqueViolation(error)
}

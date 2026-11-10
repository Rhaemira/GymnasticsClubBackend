@testable import GymnasticsClubBackend
import Vapor
import VaporTesting
import Testing
import Fluent

@Suite("Gymnastics Club API integration", .serialized)
struct GymnasticsClubBackendTests {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Root route is public")
    func publicRoot() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "/", afterResponse: { response async in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("Gymnastics Club API"))
            })
        }
    }

    @Test("Health reports database readiness")
    func healthChecksDatabase() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "/health", afterResponse: { response async throws in
                #expect(response.status == .ok)
                let body = response.body.string
                #expect(body.contains("\"status\":\"ok\""))
                #expect(body.contains("\"database\":\"ready\""))
            })
        }
    }

    @Test("Management routes reject requests without a bearer token")
    func managementRequiresAuthentication() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "/athletes", afterResponse: { response async in
                #expect(response.status == .unauthorized)
            })
            try await app.testing().test(.GET, "/analytics", afterResponse: { response async in
                #expect(response.status == .unauthorized)
            })
        }
    }

    @Test("Login rejects invalid credentials")
    func loginRejectsInvalidCredentials() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "/auth/login", beforeRequest: { request in
                try request.content.encode(LoginRequest(email: "nobody@example.test", password: "incorrect-password"))
            }, afterResponse: { response async in
                #expect(response.status == .unauthorized)
            })
        }
    }
    @Test("Valid login grants access to protected athlete routes")
    func loginAndCreateAthlete() async throws {
        try await withApp { app in
            let admin = AdminUser(email: "admin@example.test", passwordHash: try Bcrypt.hash("correct-horse-battery-staple"))
            try await admin.save(on: app.db)
            try await app.testing().test(.POST, "/auth/login", beforeRequest: { request in
                try request.content.encode(LoginRequest(email: "admin@example.test", password: "correct-horse-battery-staple"))
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let login = try response.content.decode(LoginResponse.self)
                try await app.testing().test(.POST, "/athletes", beforeRequest: { request in
                    request.headers.add(name: "Authorization", value: "Bearer \(login.token)")
                    try request.content.encode(WriteAthleteDTO(fullName: "Taylor Gymnast", age: 14, level: "Beginner"))
                }, afterResponse: { created async throws in
                    #expect(created.status == .ok)
                    let athletes = try await Athlete.query(on: app.db).all()
                    #expect(athletes.count == 1)
                    #expect(athletes.first?.fullName == "Taylor Gymnast")
                })
            })
        }
    }

    @Test("Athlete validation rejects invalid ages and whitespace-only names")
    func invalidAthleteIsRejected() async throws {
        try await withApp { app in
            let admin = AdminUser(email: "admin-validation@example.test", passwordHash: try Bcrypt.hash("correct-horse-battery-staple"))
            try await admin.save(on: app.db)
            let rawToken = SecureAccessToken.generate()
            let adminID = try admin.requireID()
            try await AccessToken(userID: adminID, tokenHash: SecureAccessToken.digest(rawToken), expiresAt: .distantFuture).save(on: app.db)
            try await app.testing().test(.POST, "/athletes", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(rawToken)")
                try request.content.encode(WriteAthleteDTO(fullName: "   ", age: 0, level: "Beginner"))
            }, afterResponse: { response async in
                #expect(response.status == .badRequest)
            })
        }
    }

}


extension GymnasticsClubBackendTests {
    private func makeAuthenticatedToken(on app: Application, email: String) async throws -> String {
        let admin = AdminUser(
            email: email,
            passwordHash: try Bcrypt.hash("correct-horse-battery-staple")
        )
        try await admin.save(on: app.db)
        let token = SecureAccessToken.generate()
        try await AccessToken(
            userID: admin.requireID(),
            tokenHash: SecureAccessToken.digest(token),
            expiresAt: .distantFuture
        ).save(on: app.db)
        return token
    }

    @Test("Enrollment rejects duplicates and enforces class capacity")
    func enrollmentEnforcesCapacity() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "enrollment-capacity@example.test")
            let coach = Coach(fullName: "Capacity Coach", specialty: "Artistic")
            let firstAthlete = Athlete(fullName: "Capacity Athlete One", age: 12, level: "Beginner")
            let secondAthlete = Athlete(fullName: "Capacity Athlete Two", age: 13, level: "Beginner")
            try await coach.save(on: app.db)
            try await firstAthlete.save(on: app.db)
            try await secondAthlete.save(on: app.db)
            let gymClass = Class(name: "Capacity Class", capacity: 1, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)

            let firstRequest = CreateEnrollmentDTO(
                athleteID: try firstAthlete.requireID(),
                classID: try gymClass.requireID()
            )
            try await app.testing().test(.POST, "/enrollments", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(firstRequest)
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            try await app.testing().test(.POST, "/enrollments", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(firstRequest)
            }, afterResponse: { response async in
                #expect(response.status == .conflict)
            })

            let secondRequest = CreateEnrollmentDTO(
                athleteID: try secondAthlete.requireID(),
                classID: try gymClass.requireID()
            )
            try await app.testing().test(.POST, "/enrollments", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(secondRequest)
            }, afterResponse: { response async in
                #expect(response.status == .conflict)
            })
            #expect(try await Enrollment.query(on: app.db).count() == 1)
        }
    }

    @Test("Concurrent enrollment inserts cannot exceed class capacity")
    func concurrentEnrollmentRespectsCapacity() async throws {
        try await withApp { app in
            let coach = Coach(fullName: "Concurrent Coach", specialty: "Artistic")
            try await coach.save(on: app.db)
            let gymClass = Class(name: "Concurrent Class", capacity: 2, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)

            var athleteIDs: [UUID] = []
            for index in 0..<8 {
                let athlete = Athlete(fullName: "Concurrent Athlete \(index)", age: 10 + index, level: "Beginner")
                try await athlete.save(on: app.db)
                athleteIDs.append(try athlete.requireID())
            }

            let database = app.db
            let classID = try gymClass.requireID()
            let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for athleteID in athleteIDs {
                    group.addTask {
                        do {
                            try await Enrollment(athleteID: athleteID, classID: classID).save(on: database)
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                var values: [Bool] = []
                for await value in group { values.append(value) }
                return values
            }

            #expect(outcomes.filter { $0 }.count == 2)
            #expect(try await Enrollment.query(on: app.db).count() == 2)
        }
    }

    @Test("Attendance rejects duplicate athlete, class and timestamp records")
    func attendanceRejectsDuplicateTimestamp() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "attendance-unique@example.test")
            let coach = Coach(fullName: "Attendance Coach", specialty: "Artistic")
            let athlete = Athlete(fullName: "Attendance Athlete", age: 12, level: "Beginner")
            try await coach.save(on: app.db)
            try await athlete.save(on: app.db)
            let gymClass = Class(name: "Attendance Class", capacity: 10, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)
            let payload = CreateAttendanceDTO(
                athleteID: try athlete.requireID(),
                classID: try gymClass.requireID(),
                attendedOn: Date(timeIntervalSince1970: 1_700_000_000.125)
            )

            try await app.testing().test(.POST, "/attendance", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(payload)
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            try await app.testing().test(.POST, "/attendance", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(payload)
            }, afterResponse: { response async in
                #expect(response.status == .conflict)
            })
            #expect(try await Attendance.query(on: app.db).count() == 1)
        }
    }

    @Test("Expired bearer tokens are rejected")
    func expiredTokenIsRejected() async throws {
        try await withApp { app in
            let admin = AdminUser(email: "expired-token@example.test", passwordHash: try Bcrypt.hash("correct-horse-battery-staple"))
            try await admin.save(on: app.db)
            let token = SecureAccessToken.generate()
            try await AccessToken(
                userID: admin.requireID(),
                tokenHash: SecureAccessToken.digest(token),
                expiresAt: .distantPast
            ).save(on: app.db)

            try await app.testing().test(.GET, "/auth/me", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .unauthorized)
            })
        }
    }

    @Test("Logout revokes the presented token")
    func logoutRevokesToken() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "logout@example.test")
            try await app.testing().test(.POST, "/auth/logout", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .noContent)
            })
            try await app.testing().test(.GET, "/auth/me", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .unauthorized)
            })
        }
    }

    @Test("Athlete deletion transaction removes related enrollment and attendance")
    func athleteDeletionPreservesReferentialIntegrity() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "delete-athlete@example.test")
            let coach = Coach(fullName: "Deletion Coach", specialty: "Artistic")
            let athlete = Athlete(fullName: "Deletion Athlete", age: 12, level: "Beginner")
            try await coach.save(on: app.db)
            try await athlete.save(on: app.db)
            let gymClass = Class(name: "Deletion Class", capacity: 10, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)
            try await Enrollment(athleteID: athlete.requireID(), classID: gymClass.requireID()).save(on: app.db)
            try await Attendance(
                athleteID: athlete.requireID(),
                classID: gymClass.requireID(),
                attendedOn: Date(timeIntervalSince1970: 1_700_000_000)
            ).save(on: app.db)

            try await app.testing().test(.DELETE, "/athletes/\(try athlete.requireID())", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            #expect(try await Athlete.query(on: app.db).count() == 0)
            #expect(try await Enrollment.query(on: app.db).count() == 0)
            #expect(try await Attendance.query(on: app.db).count() == 0)
        }
    }

    @Test("Class capacity cannot be reduced below existing enrollments")
    func classCapacityCannotUndercutEnrollments() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "class-capacity-update@example.test")
            let coach = Coach(fullName: "Update Capacity Coach", specialty: "Artistic")
            let firstAthlete = Athlete(fullName: "Update Capacity Athlete One", age: 12, level: "Beginner")
            let secondAthlete = Athlete(fullName: "Update Capacity Athlete Two", age: 13, level: "Beginner")
            try await coach.save(on: app.db)
            try await firstAthlete.save(on: app.db)
            try await secondAthlete.save(on: app.db)
            let gymClass = Class(name: "Update Capacity Class", capacity: 2, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)
            try await Enrollment(athleteID: firstAthlete.requireID(), classID: gymClass.requireID()).save(on: app.db)
            try await Enrollment(athleteID: secondAthlete.requireID(), classID: gymClass.requireID()).save(on: app.db)

            try await app.testing().test(.PUT, "/classes/\(try gymClass.requireID())", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateClassDTO(
                    name: "Update Capacity Class",
                    capacity: 1,
                    coachID: try coach.requireID()
                ))
            }, afterResponse: { response async in
                #expect(response.status == .conflict)
            })
        }
    }

    @Test("Reports and analytics return their documented payloads")
    func reportsAndAnalyticsAreAvailableToAuthenticatedUsers() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "analytics@example.test")
            try await app.testing().test(.GET, "/reports", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                _ = try response.content.decode(ReportsResponse.self)
            })
            try await app.testing().test(.GET, "/analytics", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                _ = try response.content.decode(AnalyticsResponse.self)
            })
        }
    }
}


extension GymnasticsClubBackendTests {
    @Test("Athlete HTTP routes support create, list, update and delete")
    func athleteCRUDRoutes() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "athlete-crud@example.test")
            try await app.testing().test(.POST, "/athletes", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(WriteAthleteDTO(fullName: "CRUD Athlete", age: 11, level: "Beginner"))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            let created = try await Athlete.query(on: app.db)
                .filter(\.$fullName == "CRUD Athlete")
                .first()
            let id = try #require(created?.id)

            try await app.testing().test(.GET, "/athletes", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let records = try response.content.decode([Athlete].self)
                #expect(records.contains { $0.id == id && $0.fullName == "CRUD Athlete" })
            })
            try await app.testing().test(.PUT, "/athletes/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(WriteAthleteDTO(fullName: "Updated Athlete", age: 12, level: "Intermediate"))
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let updated = try response.content.decode(Athlete.self)
                #expect(updated.fullName == "Updated Athlete")
                #expect(updated.age == 12)
            })
            try await app.testing().test(.DELETE, "/athletes/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            #expect(try await Athlete.find(id, on: app.db) == nil)
        }
    }

    @Test("Coach HTTP routes support create, list, update and delete")
    func coachCRUDRoutes() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "coach-crud@example.test")
            try await app.testing().test(.POST, "/coaches", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(WriteCoachDTO(fullName: "CRUD Coach", specialty: "Artistic"))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            let created = try await Coach.query(on: app.db)
                .filter(\.$fullName == "CRUD Coach")
                .first()
            let id = try #require(created?.id)

            try await app.testing().test(.GET, "/coaches", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let records = try response.content.decode([Coach].self)
                #expect(records.contains { $0.id == id && $0.fullName == "CRUD Coach" })
            })
            try await app.testing().test(.PUT, "/coaches/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(WriteCoachDTO(fullName: "Updated Coach", specialty: "Rhythmic"))
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let updated = try response.content.decode(Coach.self)
                #expect(updated.fullName == "Updated Coach")
                #expect(updated.specialty == "Rhythmic")
            })
            try await app.testing().test(.DELETE, "/coaches/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            #expect(try await Coach.find(id, on: app.db) == nil)
        }
    }

    @Test("Class HTTP routes support create, list, update and transactional delete")
    func classCRUDAndCascadeRoutes() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "class-crud@example.test")
            let coach = Coach(fullName: "Class CRUD Coach", specialty: "Artistic")
            let athlete = Athlete(fullName: "Class CRUD Athlete", age: 12, level: "Beginner")
            try await coach.save(on: app.db)
            try await athlete.save(on: app.db)
            let coachID = try coach.requireID()
            let athleteID = try athlete.requireID()

            try await app.testing().test(.POST, "/classes", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateClassDTO(name: "CRUD Class", capacity: 5, coachID: coachID))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            let created = try await Class.query(on: app.db)
                .filter(\.$name == "CRUD Class")
                .first()
            let id = try #require(created?.id)

            try await app.testing().test(.GET, "/classes", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let records = try response.content.decode([ClassResponse].self)
                #expect(records.contains { $0.id == id && $0.name == "CRUD Class" && $0.coach.id == coachID })
            })

            try await app.testing().test(.POST, "/enrollments", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateEnrollmentDTO(athleteID: athleteID, classID: id))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            try await app.testing().test(.POST, "/attendance", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateAttendanceDTO(
                    athleteID: athleteID,
                    classID: id,
                    attendedOn: Date(timeIntervalSince1970: 1_700_000_010)
                ))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            try await app.testing().test(.PUT, "/classes/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateClassDTO(name: "Updated CRUD Class", capacity: 8, coachID: coachID))
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let updated = try response.content.decode(ClassResponse.self)
                #expect(updated.name == "Updated CRUD Class")
                #expect(updated.capacity == 8)
            })

            try await app.testing().test(.DELETE, "/classes/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            #expect(try await Class.find(id, on: app.db) == nil)
            #expect(try await Enrollment.query(on: app.db).count() == 0)
            #expect(try await Attendance.query(on: app.db).count() == 0)
        }
    }

    @Test("Attendance HTTP routes support create, list, update and delete")
    func attendanceCRUDRoutes() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "attendance-crud@example.test")
            let coach = Coach(fullName: "Attendance CRUD Coach", specialty: "Artistic")
            let athlete = Athlete(fullName: "Attendance CRUD Athlete", age: 12, level: "Beginner")
            try await coach.save(on: app.db)
            try await athlete.save(on: app.db)
            let gymClass = Class(name: "Attendance CRUD Class", capacity: 5, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)
            let firstDate = Date(timeIntervalSince1970: 1_700_000_020)
            let secondDate = Date(timeIntervalSince1970: 1_700_000_030)

            try await app.testing().test(.POST, "/attendance", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateAttendanceDTO(
                    athleteID: try athlete.requireID(),
                    classID: try gymClass.requireID(),
                    attendedOn: firstDate
                ))
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            let created = try await Attendance.query(on: app.db)
                .filter(\.$athlete.$id == (try athlete.requireID()))
                .filter(\.$gymClass.$id == (try gymClass.requireID()))
                .filter(\.$attendedOn == firstDate)
                .first()
            let id = try #require(created?.id)

            try await app.testing().test(.GET, "/attendance", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let records = try response.content.decode([AttendanceResponse].self)
                #expect(records.contains { $0.id == id })
            })
            try await app.testing().test(.PUT, "/attendance/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
                try request.content.encode(CreateAttendanceDTO(
                    athleteID: try athlete.requireID(),
                    classID: try gymClass.requireID(),
                    attendedOn: secondDate
                ))
            }, afterResponse: { response async throws in
                #expect(response.status == .ok)
                let updated = try response.content.decode(AttendanceResponse.self)
                #expect(abs(updated.attendedOn.timeIntervalSince(secondDate)) < 0.001)
            })
            try await app.testing().test(.DELETE, "/attendance/\(id)", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })
            #expect(try await Attendance.find(id, on: app.db) == nil)
        }
    }

    @Test("Coach deletion transaction removes associated classes, enrollments and attendance")
    func coachDeletionPreservesReferentialIntegrity() async throws {
        try await withApp { app in
            let token = try await makeAuthenticatedToken(on: app, email: "coach-delete@example.test")
            let coach = Coach(fullName: "Cascade Coach", specialty: "Artistic")
            let athlete = Athlete(fullName: "Cascade Athlete", age: 12, level: "Beginner")
            try await coach.save(on: app.db)
            try await athlete.save(on: app.db)
            let gymClass = Class(name: "Cascade Class", capacity: 5, coachID: try coach.requireID())
            try await gymClass.save(on: app.db)
            try await Enrollment(athleteID: try athlete.requireID(), classID: try gymClass.requireID()).save(on: app.db)
            try await Attendance(
                athleteID: try athlete.requireID(),
                classID: try gymClass.requireID(),
                attendedOn: Date(timeIntervalSince1970: 1_700_000_040)
            ).save(on: app.db)

            try await app.testing().test(.DELETE, "/coaches/\(try coach.requireID())", beforeRequest: { request in
                request.headers.add(name: "Authorization", value: "Bearer \(token)")
            }, afterResponse: { response async in
                #expect(response.status == .ok)
            })

            #expect(try await Coach.query(on: app.db).count() == 0)
            #expect(try await Class.query(on: app.db).count() == 0)
            #expect(try await Enrollment.query(on: app.db).count() == 0)
            #expect(try await Attendance.query(on: app.db).count() == 0)
        }
    }
}


extension GymnasticsClubBackendTests {
    @Test("Login throttling limits repeated failures and recovers after its window")
    func loginRateLimiterEnforcesWindow() async {
        let limiter = LoginRateLimiter()
        let key = "test-account"
        let start = Date(timeIntervalSince1970: 1_000)

        for attempt in 0..<5 {
            #expect(await limiter.isAllowed(key, now: start.addingTimeInterval(TimeInterval(attempt))))
            await limiter.recordFailure(key, now: start.addingTimeInterval(TimeInterval(attempt)))
        }

        #expect(!(await limiter.isAllowed(key, now: start.addingTimeInterval(30))))
        #expect(await limiter.isAllowed(key, now: start.addingTimeInterval(61)))
    }

    @Test("Successful login resets that limiter key")
    func loginRateLimiterResetsAfterSuccess() async {
        let limiter = LoginRateLimiter()
        let key = "test-reset"
        let now = Date(timeIntervalSince1970: 2_000)

        for attempt in 0..<5 {
            await limiter.recordFailure(key, now: now.addingTimeInterval(TimeInterval(attempt)))
        }

        #expect(!(await limiter.isAllowed(key, now: now.addingTimeInterval(10))))
        await limiter.reset(key)
        #expect(await limiter.isAllowed(key, now: now.addingTimeInterval(10)))
    }
}

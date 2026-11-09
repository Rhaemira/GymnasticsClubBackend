@testable import GymnasticsClubBackend
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

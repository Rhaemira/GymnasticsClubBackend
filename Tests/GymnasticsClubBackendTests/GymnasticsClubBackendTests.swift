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
}

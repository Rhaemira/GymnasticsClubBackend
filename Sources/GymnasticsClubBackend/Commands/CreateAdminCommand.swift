import Fluent
import ConsoleKit
import Vapor

struct CreateAdminCommand: AsyncCommand {
    struct Signature: CommandSignature {
        init() {}
    }

    let signature = Signature()

    var help: String {
        "Create the initial administrator using ADMIN_EMAIL and ADMIN_INITIAL_PASSWORD."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard
            let rawEmail = Environment.get("ADMIN_EMAIL"),
            let password = Environment.get("ADMIN_INITIAL_PASSWORD")
        else {
            throw Abort(.badRequest, reason: "Set ADMIN_EMAIL and ADMIN_INITIAL_PASSWORD.")
        }

        let normalized = try RequestValidation.administrator(email: rawEmail, password: password)
        if try await AdminUser.query(on: context.application.db)
            .filter(\.$email == normalized)
            .first() != nil {
            throw Abort(.conflict, reason: "An administrator with that email already exists.")
        }

        let administrator = AdminUser(email: normalized, passwordHash: try Bcrypt.hash(password))
        do {
            try await administrator.save(on: context.application.db)
        } catch {
            let details = String(reflecting: error).lowercased()
            if details.contains("23505") || details.contains("unique constraint") {
                throw Abort(.conflict, reason: "An administrator with that email already exists.")
            }
            throw error
        }
        context.console.print("Administrator created.")
    }
}

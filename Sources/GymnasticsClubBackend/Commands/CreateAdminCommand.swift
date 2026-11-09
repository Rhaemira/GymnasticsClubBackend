import Fluent
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
            let email = Environment.get("ADMIN_EMAIL")?.trimmingCharacters(in: .whitespacesAndNewlines),
            let password = Environment.get("ADMIN_INITIAL_PASSWORD"),
            !email.isEmpty,
            password.count >= 12
        else {
            throw Abort(
                .badRequest,
                reason: "Set ADMIN_EMAIL and ADMIN_INITIAL_PASSWORD (at least 12 characters)."
            )
        }

        let normalized = email.lowercased()
        if try await AdminUser.query(on: context.application.db)
            .filter(\.$email == normalized)
            .first() != nil {
            throw Abort(.conflict, reason: "An administrator with that email already exists.")
        }

        let passwordHash = try Bcrypt.hash(password)
        let administrator = AdminUser(email: normalized, passwordHash: passwordHash)
        try await administrator.save(on: context.application.db)
        context.console.print("Administrator created.")
    }
}

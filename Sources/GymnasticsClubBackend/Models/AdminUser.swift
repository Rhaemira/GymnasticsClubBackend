import Fluent
import Vapor

final class AdminUser: Model, Authenticatable, @unchecked Sendable {
    static let schema = "admin_users"
    @ID(key: .id) var id: UUID?
    @Field(key: "email") var email: String
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "created_at") var createdAt: Date
    init() {}
    init(email: String, passwordHash: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.passwordHash = passwordHash
        self.createdAt = .now
    }
}

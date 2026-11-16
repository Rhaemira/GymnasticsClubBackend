import Fluent
import Foundation

final class AccessToken: Model, @unchecked Sendable {
    static let schema = "access_tokens"
    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: AdminUser
    @Field(key: "token_hash") var tokenHash: String
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "revoked_at") var revokedAt: Date?
    @Field(key: "created_at") var createdAt: Date
    init() {}
    init(userID: UUID, tokenHash: String, expiresAt: Date) {
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
        self.revokedAt = nil
        self.createdAt = .now
    }
}

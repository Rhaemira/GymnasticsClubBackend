import Crypto
import Fluent
import Foundation
import Vapor

struct AccessTokenAuthenticator: AsyncBearerAuthenticator {
    typealias User = AdminUser
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let digest = SHA256.hash(data: Data(bearer.token.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let token = try await AccessToken.query(on: request.db)
            .filter(\.$tokenHash == digest).with(\.$user).first(),
            token.revokedAt == nil, token.expiresAt > .now else { return }
        request.auth.login(token.user)
    }
}

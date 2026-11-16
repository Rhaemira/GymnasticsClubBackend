import Vapor
struct LoginRequest: Content { let email: String; let password: String }
struct AdminUserResponse: Content { let id: UUID; let email: String }
struct LoginResponse: Content { let token: String; let expiresAt: Date; let user: AdminUserResponse }

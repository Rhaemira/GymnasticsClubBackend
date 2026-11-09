import Foundation
actor LoginRateLimiter {
    private var failures: [String: [Date]] = [:]
    private let limit = 5
    private let window: TimeInterval = 60
    func isAllowed(_ key: String, now: Date = .now) -> Bool {
        let recent = (failures[key] ?? []).filter { now.timeIntervalSince($0) < window }
        failures[key] = recent
        return recent.count < limit
    }
    func recordFailure(_ key: String, now: Date = .now) {
        failures[key] = (failures[key] ?? []).filter { now.timeIntervalSince($0) < window } + [now]
    }
    func reset(_ key: String) { failures[key] = nil }
}
let loginRateLimiter = LoginRateLimiter()

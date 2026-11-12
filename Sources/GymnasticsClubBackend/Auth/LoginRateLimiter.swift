import Foundation
import Vapor

/// Process-local failed-login throttle. Tracking is bounded so attempts using
/// many distinct account identifiers cannot grow this dictionary indefinitely.
/// Multi-instance deployments must use a shared limiter at the edge.
actor LoginRateLimiter {
    private var failures: [String: [Date]] = [:]
    private let limit = 5
    private let window: TimeInterval = 60
    private let maximumTrackedKeys = 10_000

    func isAllowed(_ key: String, now: Date = .now) -> Bool {
        pruneExpired(now: now)
        let recent = recentFailures(for: key, now: now)
        if recent.isEmpty {
            failures.removeValue(forKey: key)
        } else {
            failures[key] = recent
        }
        return recent.count < limit
    }

    func recordFailure(_ key: String, now: Date = .now) {
        pruneExpired(now: now)
        var recent = recentFailures(for: key, now: now)
        guard recent.count < limit else { return }

        if failures[key] == nil, failures.count >= maximumTrackedKeys {
            evictOldestKey()
        }

        recent.append(now)
        failures[key] = recent
    }

    func reset(_ key: String) {
        failures.removeValue(forKey: key)
    }

    private func recentFailures(for key: String, now: Date) -> [Date] {
        (failures[key] ?? []).filter {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age < window
        }
    }

    private func pruneExpired(now: Date) {
        for key in Array(failures.keys) {
            let recent = recentFailures(for: key, now: now)
            if recent.isEmpty {
                failures.removeValue(forKey: key)
            } else {
                failures[key] = recent
            }
        }
    }

    private func evictOldestKey() {
        guard let oldest = failures.min(by: {
            ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast)
        })?.key else { return }
        failures.removeValue(forKey: oldest)
    }
}

struct LoginRateLimiterKey: StorageKey {
    typealias Value = LoginRateLimiter
}

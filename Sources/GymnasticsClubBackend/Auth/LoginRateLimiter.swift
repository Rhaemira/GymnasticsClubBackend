import Foundation
import Vapor

/// Process-local failed-login throttle with atomic in-flight reservations.
/// Tracking is bounded; multi-instance deployments must use a shared limiter
/// at the edge or a shared datastore.
actor LoginRateLimiter {
    private var failures: [String: [Date]] = [:]
    private var inFlight: [String: Set<UUID>] = [:]
    private let limit = 5
    private let window: TimeInterval = 60
    private let maximumTrackedKeys = 10_000

    /// Atomically reserves one attempt against every supplied key. Reserving
    /// before password verification prevents concurrent requests from all
    /// passing the same last available slot.
    func beginAttempt(for keys: [String], now: Date = .now) -> UUID? {
        let uniqueKeys = Array(Set(keys)).sorted()
        guard !uniqueKeys.isEmpty else { return nil }

        for key in uniqueKeys {
            let recent = recentFailures(for: key, now: now)
            if recent.isEmpty {
                failures.removeValue(forKey: key)
            } else {
                failures[key] = recent
            }
        }

        guard uniqueKeys.allSatisfy({
            (failures[$0]?.count ?? 0) + (inFlight[$0]?.count ?? 0) < limit
        }) else {
            return nil
        }

        let newKeys = uniqueKeys.filter { failures[$0] == nil && inFlight[$0] == nil }
        let requiredEvictions = max(0, trackedKeyCount + newKeys.count - maximumTrackedKeys)
        if requiredEvictions > 0 {
            let excluded = Set(uniqueKeys)
            let victims = failures
                .filter { !excluded.contains($0.key) && (inFlight[$0.key]?.isEmpty ?? true) }
                .sorted {
                    ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast)
                }
                .prefix(requiredEvictions)

            guard victims.count == requiredEvictions else { return nil }
            for victim in victims {
                failures.removeValue(forKey: victim.key)
            }
        }

        let attemptID = UUID()
        for key in uniqueKeys {
            inFlight[key, default: []].insert(attemptID)
        }
        return attemptID
    }

    /// Converts the reservation into a failed attempt for every key.
    func recordFailure(_ attemptID: UUID, for keys: [String], now: Date = .now) {
        for key in Set(keys) {
            removeReservation(attemptID, for: key)
            let recent = recentFailures(for: key, now: now)
            if recent.count < limit {
                failures[key] = recent + [now]
            }
        }
    }

    /// Releases the in-flight reservation and resets only the authenticated
    /// account's failure history. Failures from the same source IP remain.
    func recordSuccess(_ attemptID: UUID, accountKey: String, for keys: [String]) {
        for key in Set(keys) {
            removeReservation(attemptID, for: key)
        }
        failures.removeValue(forKey: accountKey)
    }

    /// Releases a reservation when the request fails for an infrastructure or
    /// cancellation reason rather than an incorrect credential.
    func cancelAttempt(_ attemptID: UUID, for keys: [String]) {
        for key in Set(keys) {
            removeReservation(attemptID, for: key)
        }
    }

    private var trackedKeyCount: Int {
        Set(failures.keys).union(inFlight.keys).count
    }

    private func removeReservation(_ attemptID: UUID, for key: String) {
        inFlight[key]?.remove(attemptID)
        if inFlight[key]?.isEmpty == true {
            inFlight.removeValue(forKey: key)
        }
    }

    private func recentFailures(for key: String, now: Date) -> [Date] {
        (failures[key] ?? []).filter {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age < window
        }
    }
}

struct LoginRateLimiterKey: StorageKey {
    typealias Value = LoginRateLimiter
}

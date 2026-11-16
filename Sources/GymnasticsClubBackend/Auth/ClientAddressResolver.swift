import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Resolves the address used by the process-local login throttle.
/// Forwarded identity is accepted only from an explicitly trusted immediate
/// proxy. The proxy must overwrite X-Real-IP rather than append client input.
enum ClientAddressResolver {
    static func resolve(remoteAddress: String?, realIPHeader: String?, trustedProxyIPs: Set<String>) -> String {
        guard let remoteAddress, isIPAddress(remoteAddress) else { return "unknown" }
        guard trustedProxyIPs.contains(remoteAddress), let realIPHeader, isIPAddress(realIPHeader) else {
            return remoteAddress
        }
        return realIPHeader
    }

    static func isIPAddress(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }

        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }

        var ipv6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }
}

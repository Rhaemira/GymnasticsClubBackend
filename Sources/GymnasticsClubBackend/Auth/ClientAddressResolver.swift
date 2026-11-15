import Foundation

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
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address == value else { return false }
        if address.contains(".") && !address.contains(":") {
            let octets = address.split(separator: ".", omittingEmptySubsequences: false)
            return octets.count == 4 && octets.allSatisfy { octet in
                guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                      let number = Int(octet) else { return false }
                return (0...255).contains(number)
            }
        }
        if address.contains(":") {
            return address.filter { $0 == ":" }.count >= 2 && address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        return false
    }
}

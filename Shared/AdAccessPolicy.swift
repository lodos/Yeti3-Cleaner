import Foundation

/// A server-confirmed grant is the only source of ad-free access.
enum AdAccessPolicy {
    static func expiry(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        let value = raw.contains("+") || raw.hasSuffix("Z") || raw.dropFirst(10).contains("-") ? raw : raw + "Z"
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func allows(_ result: [String: Any], now: Date = Date()) -> Bool {
        guard result["ads_enabled"] as? Bool == false else { return false }
        if let raw = result["expires_at"] as? String { return expiry(raw).map { $0 > now } ?? false }
        // Only an audited administrator may grant perpetual access.
        return result["source"] as? String == "ADMIN"
    }
}

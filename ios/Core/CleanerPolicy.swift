import Foundation

enum Strategy: String, CaseIterable, Codable, Identifiable {
    case safe, balanced, manual
    var id: String { rawValue }
    var title: String { switch self { case .safe: return "Безопасная"; case .balanced: return "Средняя"; case .manual: return "Ручная" } }
    var detail: String { switch self {
    case .safe: return "Точные дубликаты и крупные объекты. Всё выбираете вы."
    case .balanced: return "Дополнительно: похожие фото и старые скриншоты. Рекомендации требуют просмотра."
    case .manual: return "Настройте категории и выбирайте каждый объект самостоятельно."
    } }
}
struct ScanOptions: Codable, Equatable {
    var photos = true
    var contacts = false
    var files = true
    var similar = false
    var screenshots = false
    var screenshotDays = 90
    var largeMegabytes = 100
    var jpegQuality = 0.85
    var maxPixel = 2560
    static func preset(_ strategy: Strategy) -> Self {
        var result = Self()
        if strategy == .balanced { result.similar = true; result.screenshots = true; result.contacts = true }
        if strategy == .manual { result.photos = false; result.files = false }
        return result
    }
}
enum CleanerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct ContentDigest: Hashable, Sendable {
    var hash: String
    var bytes: Int64
}
enum SafetyPolicy {
    static func deletionAllowed(selected: Set<String>, known: Set<String>, duplicateGroups: [[String]]) -> Bool {
        !selected.isEmpty && selected.isSubset(of: known) && duplicateGroups.allSatisfy { group in
            !Set(group).isSubset(of: selected)
        }
    }
    static func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
    static func optimizationSavesSpace(original: Int64, output: Int64) -> Bool {
        original > 0 && output > 0 && output < original * 9 / 10
    }
    static func normalizedPhone(_ value: String) -> String { value.filter(\.isNumber) }
}
func bytesLabel(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

// Automation never authorizes deletion of personal data.
struct AutomationPolicy: Codable, Equatable {
    var enabled = false
    var intervalHours = 24
    var minimumBatteryPercent = 30
    var requireCharging = true
    func due(now: Date, lastAttempt: Date?, batteryPercent: Int?, charging: Bool,
             lowPower: Bool, thermalSafe: Bool) -> Bool {
        guard enabled, !lowPower, thermalSafe, !requireCharging || charging else { return false }
        guard charging || (batteryPercent.map { $0 >= minimumBatteryPercent } ?? false) else { return false }
        return lastAttempt.map { now.timeIntervalSince($0) >= Double(max(1, intervalHours)) * 3600 } ?? true
    }
}
struct CleanupDryRun: Equatable {
    let selected: Set<String>
    let estimatedBytes: Int64
    let generatedAt: Date
    let scanDate: Date?
    let allowed: Bool
    static func make(selected: Set<String>, sizes: [String: Int64], groups: [[String]], scanDate: Date?, now: Date = Date()) -> Self {
        .init(selected: selected, estimatedBytes: selected.reduce(0) { $0 + max(0, sizes[$1] ?? 0) }, generatedAt: now,
              scanDate: scanDate, allowed: scanDate != nil && SafetyPolicy.deletionAllowed(selected: selected, known: Set(sizes.keys), duplicateGroups: groups))
    }
    func isCurrent(selection: Set<String>, scanDate: Date?, now: Date = Date()) -> Bool {
        allowed && selection == selected && self.scanDate == scanDate && now.timeIntervalSince(generatedAt) < 900 && now >= generatedAt
    }
}

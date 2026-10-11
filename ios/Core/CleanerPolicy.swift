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
    var recentProtectionDays = 7
    var includeVideos = true
    var largeVideoMegabytes = 250
    var minimumVideoSeconds = 30
    var similarityDistance = 6
    var similarityWindowSeconds = 120
    var photoLimit = 2000
    var analysisSeconds = 120
    var economical = true
    var minimumFileKilobytes = 0
    var fileLimit = 3000
    var excludedExtensions = "key,pem,p12,mobileprovision"
    var archivesOnly = false
    var minimumOptimizationPercent = 10
    var matchContactPhones = true
    var matchContactEmails = true
    var showIncompleteContacts = true
    var minimumPhoneDigits = 7
    var includedExtensions = ""
    var excludedFolderNames = "node_modules,.git,Pods"
    var maximumFileMegabytes = 0
    var minimumFileAgeDays = 0
    var directoryDepth = 0
    var photoLookbackDays = 0
    var protectBursts = true
    var allowFairThermalState = true
    var economicalPauseMilliseconds = 20
    var continueInBackground = false
    func includesPhoto(date: Date?, now: Date = Date()) -> Bool {
        photoLookbackDays <= 0 || date.map { $0 >= now.addingTimeInterval(-Double(photoLookbackDays) * 86400) } == true
    }
    func includesFileDate(_ date: Date?, now: Date = Date()) -> Bool {
        minimumFileAgeDays <= 0 || date.map { $0 <= now.addingTimeInterval(-Double(minimumFileAgeDays) * 86400) } == true
    }
    func excludesFolder(_ name: String) -> Bool {
        Set(excludedFolderNames.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).contains(name.lowercased())
    }
    func protects(date: Date?, now: Date = Date()) -> Bool {
        recentProtectionDays > 0 && (date == nil || date! > now.addingTimeInterval(-Double(recentProtectionDays) * 86400))
    }
    func includesFile(_ url: URL, bytes: Int64) -> Bool {
        let excluded = Set(excludedExtensions.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "") })
        let ext = url.pathExtension.lowercased()
        let included = Set(includedExtensions.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "") })
        return !excluded.contains(ext) && (included.isEmpty || included.contains(ext))
            && (maximumFileMegabytes <= 0 || bytes <= Int64(maximumFileMegabytes) * 1024 * 1024)
            && bytes >= Int64(minimumFileKilobytes) * 1024 && (!archivesOnly || ["zip", "rar", "7z", "tar", "gz", "dmg"].contains(ext))
    }
    enum CodingKeys: String, CodingKey { case photos, contacts, files, similar, screenshots, screenshotDays, largeMegabytes, jpegQuality, maxPixel, recentProtectionDays, includeVideos, largeVideoMegabytes, minimumVideoSeconds, similarityDistance, similarityWindowSeconds, photoLimit, analysisSeconds, economical, minimumFileKilobytes, fileLimit, excludedExtensions, archivesOnly, minimumOptimizationPercent, matchContactPhones, matchContactEmails, showIncompleteContacts, minimumPhoneDigits, includedExtensions, excludedFolderNames, maximumFileMegabytes, minimumFileAgeDays, directoryDepth, photoLookbackDays, protectBursts, allowFairThermalState, economicalPauseMilliseconds, continueInBackground }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photos = try c.decodeIfPresent(Bool.self, forKey: .photos) ?? true
        contacts = try c.decodeIfPresent(Bool.self, forKey: .contacts) ?? false
        files = try c.decodeIfPresent(Bool.self, forKey: .files) ?? true
        similar = try c.decodeIfPresent(Bool.self, forKey: .similar) ?? false
        screenshots = try c.decodeIfPresent(Bool.self, forKey: .screenshots) ?? false
        screenshotDays = try c.decodeIfPresent(Int.self, forKey: .screenshotDays) ?? 90
        largeMegabytes = try c.decodeIfPresent(Int.self, forKey: .largeMegabytes) ?? 100
        jpegQuality = try c.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.85
        maxPixel = try c.decodeIfPresent(Int.self, forKey: .maxPixel) ?? 2560
        recentProtectionDays = try c.decodeIfPresent(Int.self, forKey: .recentProtectionDays) ?? 7
        includeVideos = try c.decodeIfPresent(Bool.self, forKey: .includeVideos) ?? true
        largeVideoMegabytes = try c.decodeIfPresent(Int.self, forKey: .largeVideoMegabytes) ?? 250
        minimumVideoSeconds = try c.decodeIfPresent(Int.self, forKey: .minimumVideoSeconds) ?? 30
        similarityDistance = try c.decodeIfPresent(Int.self, forKey: .similarityDistance) ?? 6
        similarityWindowSeconds = try c.decodeIfPresent(Int.self, forKey: .similarityWindowSeconds) ?? 120
        photoLimit = try c.decodeIfPresent(Int.self, forKey: .photoLimit) ?? 2000
        analysisSeconds = try c.decodeIfPresent(Int.self, forKey: .analysisSeconds) ?? 120
        economical = try c.decodeIfPresent(Bool.self, forKey: .economical) ?? true
        minimumFileKilobytes = try c.decodeIfPresent(Int.self, forKey: .minimumFileKilobytes) ?? 0
        fileLimit = try c.decodeIfPresent(Int.self, forKey: .fileLimit) ?? 3000
        excludedExtensions = try c.decodeIfPresent(String.self, forKey: .excludedExtensions) ?? "key,pem,p12,mobileprovision"
        archivesOnly = try c.decodeIfPresent(Bool.self, forKey: .archivesOnly) ?? false
        minimumOptimizationPercent = try c.decodeIfPresent(Int.self, forKey: .minimumOptimizationPercent) ?? 10
        matchContactPhones = try c.decodeIfPresent(Bool.self, forKey: .matchContactPhones) ?? true
        matchContactEmails = try c.decodeIfPresent(Bool.self, forKey: .matchContactEmails) ?? true
        showIncompleteContacts = try c.decodeIfPresent(Bool.self, forKey: .showIncompleteContacts) ?? true
        minimumPhoneDigits = try c.decodeIfPresent(Int.self, forKey: .minimumPhoneDigits) ?? 7
        includedExtensions = try c.decodeIfPresent(String.self, forKey: .includedExtensions) ?? ""
        excludedFolderNames = try c.decodeIfPresent(String.self, forKey: .excludedFolderNames) ?? "node_modules,.git,Pods"
        maximumFileMegabytes = try c.decodeIfPresent(Int.self, forKey: .maximumFileMegabytes) ?? 0
        minimumFileAgeDays = try c.decodeIfPresent(Int.self, forKey: .minimumFileAgeDays) ?? 0
        directoryDepth = try c.decodeIfPresent(Int.self, forKey: .directoryDepth) ?? 0
        photoLookbackDays = try c.decodeIfPresent(Int.self, forKey: .photoLookbackDays) ?? 0
        protectBursts = try c.decodeIfPresent(Bool.self, forKey: .protectBursts) ?? true
        allowFairThermalState = try c.decodeIfPresent(Bool.self, forKey: .allowFairThermalState) ?? true
        economicalPauseMilliseconds = try c.decodeIfPresent(Int.self, forKey: .economicalPauseMilliseconds) ?? 20
        continueInBackground = try c.decodeIfPresent(Bool.self, forKey: .continueInBackground) ?? false
    }
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

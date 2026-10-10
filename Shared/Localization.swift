import Foundation

/// Localizes legacy dynamic presentation text while leaving model IDs and data unchanged.
/// Templates match whole messages and preserve every inserted value verbatim.
enum YetiL10n {
    private static let cache = NSCache<NSString, NSString>()
    private static let templateKeys: [String] = {
        guard let url = Bundle.main.url(forResource: "LocalizationTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return keys
    }()
    private static let templates: [(String, NSRegularExpression)] = templateKeys.compactMap { key in
        let parts = key.components(separatedBy: "{LC")
        guard parts.count > 1 else { return nil }
        var pattern = "^" + NSRegularExpression.escapedPattern(for: parts[0])
        for part in parts.dropFirst() {
            guard let close = part.firstIndex(of: "}") else { return nil }
            pattern += "(.*?)" + NSRegularExpression.escapedPattern(for: String(part[part.index(after: close)...]))
        }
        guard let expression = try? NSRegularExpression(pattern: pattern + "\\z", options: [.dotMatchesLineSeparators]) else { return nil }
        return (key, expression)
    }
    static func text(_ source: String) -> String {
        let raw = UserDefaults.standard.string(forKey: "selectedAppLanguage") ?? "system"
        let language = raw == "system" ? (Locale.preferredLanguages.first ?? "ru") : raw
        let cacheKey = (language + "\u{0}" + source) as NSString
        if let value = cache.object(forKey: cacheKey) { return value as String }
        let selected = raw == "system" ? Bundle.main : Bundle.main.path(forResource: raw, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        var value = selected.localizedString(forKey: source, value: source, table: nil)
        if value == source && source.count <= 8192 {
            for (key, expression) in templates {
                guard let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { continue }
                let translated = selected.localizedString(forKey: key, value: key, table: nil)
                guard translated != key else { continue }
                value = translated
                // Replace placeholders in one pass so inserted values are never interpreted as templates.
                if let placeholders = try? NSRegularExpression(pattern: "\\{LC([0-9]+)\\}") {
                    let hits = placeholders.matches(in: translated, range: NSRange(translated.startIndex..., in: translated))
                    for hit in hits.reversed() {
                        guard let indexRange = Range(hit.range(at: 1), in: translated),
                              let index = Int(translated[indexRange]), index + 1 < match.numberOfRanges,
                              let captured = Range(match.range(at: index + 1), in: source),
                              let destination = Range(hit.range, in: value) else { continue }
                        value.replaceSubrange(destination, with: source[captured])
                    }
                }
                break
            }
        }
        cache.countLimit = 2048
        cache.setObject(value as NSString, forKey: cacheKey)
        return value
    }
}

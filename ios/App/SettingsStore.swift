import SwiftUI

@MainActor final class SettingsStore: ObservableObject {
    @Published var strategy: Strategy { didSet { save() } }
    @Published var profiles: [String: ScanOptions] { didSet { save() } }
    var options: ScanOptions {
        get { profiles[strategy.rawValue] ?? .preset(strategy) }
        set { profiles[strategy.rawValue] = newValue }
    }
    init() {
        strategy = Strategy(rawValue: UserDefaults.standard.string(forKey: "strategy") ?? "safe") ?? .safe
        profiles = (UserDefaults.standard.data(forKey: "profiles").flatMap { try? JSONDecoder().decode([String: ScanOptions].self, from: $0) }) ?? [:]
    }
    func reset() { profiles[strategy.rawValue] = .preset(strategy) }
    private func save() {
        UserDefaults.standard.set(strategy.rawValue, forKey: "strategy")
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles") }
    }
}

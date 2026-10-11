import SwiftUI

@MainActor final class SettingsStore: ObservableObject {
    @Published var backgroundAnalysis = UserDefaults.standard.bool(forKey: "backgroundAnalysis") { didSet { UserDefaults.standard.set(backgroundAnalysis, forKey: "backgroundAnalysis"); BackgroundAnalysis.schedule() } }
    @Published var automation: AutomationPolicy { didSet { save() } }
    @Published var strategy: Strategy { didSet { save() } }
    @Published var profiles: [String: ScanOptions] { didSet { save() } }
    var options: ScanOptions {
        get { profiles[strategy.rawValue] ?? .preset(strategy) }
        set { profiles[strategy.rawValue] = newValue }
    }
    init() {
        automation = UserDefaults.standard.data(forKey: "automation").flatMap { try? JSONDecoder().decode(AutomationPolicy.self, from: $0) } ?? AutomationPolicy()
        strategy = Strategy(rawValue: UserDefaults.standard.string(forKey: "strategy") ?? "safe") ?? .safe
        profiles = (UserDefaults.standard.data(forKey: "profiles").flatMap { try? JSONDecoder().decode([String: ScanOptions].self, from: $0) }) ?? [:]
    }
    func reset() { profiles[strategy.rawValue] = .preset(strategy) }
    private func save() {
        // A changed policy invalidates the pending system request.
        defer { BackgroundAnalysis.schedule() }
        if let data = try? JSONEncoder().encode(automation) { UserDefaults.standard.set(data, forKey: "automation") }
        UserDefaults.standard.set(strategy.rawValue, forKey: "strategy")
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles") }
    }
}

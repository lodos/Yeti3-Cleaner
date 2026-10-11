import Foundation

struct AnalysisBudget: Sendable {
    let deadline: Date
    let economical: Bool
    init(options: ScanOptions) {
        deadline = Date().addingTimeInterval(Double(max(15, min(600, options.analysisSeconds))))
        economical = options.economical
    }
    func check() throws {
        try Task.checkCancellation()
        let process = ProcessInfo.processInfo
        guard Date() < deadline else { throw CleanerError.message("Достигнут лимит времени. Увеличьте его в настройках и повторите анализ. Ничего не удалено.") }
        guard process.thermalState == .nominal || process.thermalState == .fair else { throw CleanerError.message("Анализ остановлен из-за нагрева. Повторите после охлаждения.") }
        guard !economical || !process.isLowPowerModeEnabled else { throw CleanerError.message("Экономный анализ отложен: включён режим энергосбережения.") }
    }
    func yield() async throws {
        try check()
        if economical { try await Task.sleep(for: .milliseconds(20)) }
    }
}

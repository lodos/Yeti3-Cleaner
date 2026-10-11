import BackgroundTasks
import UIKit

#if !targetEnvironment(macCatalyst)
/// One explicit analysis, visible and cancellable in the system UI. Never queued.
@available(iOS 26, *)
@MainActor final class ContinuedAnalysis {
    static let shared = ContinuedAnalysis()
    private var identifier: String?
    private var active: BGContinuedProcessingTask?
    private var waiting: CheckedContinuation<Bool, Never>?
    private var cancelAction: (() -> Void)?
    var isActive: Bool { active != nil }
    private var launchTimeout: Task<Void, Never>?

    func begin(cancel: @escaping () -> Void) async -> Bool {
        guard identifier == nil, UIApplication.shared.applicationState == .active else { return false }
        let id = (Bundle.main.bundleIdentifier ?? "ru.yeti3.cleaner.ios") + ".analysis." + UUID().uuidString
        identifier = id; cancelAction = cancel
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting = continuation
                // Register the concrete job ID: avoids wildcard dispatch problems on early iOS 26.
                // BGTaskScheduler has no unregister API; the handler captures only a weak owner and ID.
                let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
                    Task { @MainActor in
                        guard let self, self.identifier == id, self.waiting != nil,
                              let processing = task as? BGContinuedProcessingTask else {
                            task.setTaskCompleted(success: false); return
                        }
                        self.active = processing
                        processing.progress.totalUnitCount = 1000
                        processing.expirationHandler = { [weak self] in
                            Task { @MainActor in self?.cancelAction?() }
                        }
                        self.launchTimeout?.cancel(); self.launchTimeout = nil
                        self.waiting?.resume(returning: true); self.waiting = nil
                    }
                }
                guard registered else { failWaiting(id); return }
                let request = BGContinuedProcessingTaskRequest(identifier: id, title: "YETI³ Cleaner", subtitle: "Локальный анализ. Ничего не удаляется.")
                request.strategy = .fail
                // CPU-only hashing; no GPU/Neural Engine entitlements or resources.
                Task.detached(priority: .utility) {
                    do {
                        if #available(iOS 27, *) { try await BGTaskScheduler.shared.submitTaskRequest(request) }
                        else { try BGTaskScheduler.shared.submit(request) }
                    } catch { await MainActor.run { self.failWaiting(id) } }
                }
                launchTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.failWaiting(id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.failWaiting(id) }
        }
    }
    private func failWaiting(_ id: String) {
        guard identifier == id, active == nil else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
        launchTimeout?.cancel(); launchTimeout = nil
        identifier = nil; cancelAction = nil
        waiting?.resume(returning: false); waiting = nil
    }
    func update(_ fraction: Double, subtitle: String) {
        guard let active else { return }
        active.progress.completedUnitCount = max(active.progress.completedUnitCount, Int64(max(0, min(0.999, fraction)) * 1000))
        active.updateTitle("YETI³ Cleaner", subtitle: subtitle)
    }
    func finish(success: Bool) {
        guard identifier != nil else { return }
        if success { active?.progress.completedUnitCount = 1000 }
        active?.setTaskCompleted(success: success)
        active = nil; cancelAction = nil
        identifier = nil
    }
}
#endif

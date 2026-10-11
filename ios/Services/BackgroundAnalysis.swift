import BackgroundTasks
import Photos
import UIKit

final class CleanerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundAnalysis.identifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            BackgroundAnalysis.run(processing)
        }
        return true
    }
}

enum BackgroundAnalysis {
    static let identifier = (Bundle.main.bundleIdentifier ?? "ru.yeti3.cleaner.ios") + ".overview"
    static func policy() -> AutomationPolicy {
        UserDefaults.standard.data(forKey: "automation").flatMap { try? JSONDecoder().decode(AutomationPolicy.self, from: $0) } ?? AutomationPolicy()
    }
    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard UserDefaults.standard.bool(forKey: "backgroundAnalysis") else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = policy().requireCharging
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date().addingTimeInterval(Double(max(1, policy().intervalHours)) * 3600)
        Task.detached(priority: .utility) {
            do {
                if #available(iOS 27, *) { try await BGTaskScheduler.shared.submitTaskRequest(request) }
                else { try BGTaskScheduler.shared.submit(request) }
                UserDefaults.standard.removeObject(forKey: "backgroundSchedulingMessage")
            } catch { UserDefaults.standard.set("Система пока не приняла фоновую задачу. Повторим при уходе в фон.", forKey: "backgroundSchedulingMessage") }
        }
    }
    static func run(_ task: BGProcessingTask) {
        // Expiration cancels the same structured worker, even during metadata enumeration.
        let worker = Task { @MainActor () -> Bool in
            guard UserDefaults.standard.bool(forKey: "backgroundAnalysis") else { return false }
            let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard access == .authorized || access == .limited else { return false }
            UIDevice.current.isBatteryMonitoringEnabled = true
            let device = UIDevice.current
            let charging = device.batteryState == .charging || device.batteryState == .full
            let level = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
            var policy = policy(); policy.enabled = true // independent explicit background opt-in
            guard policy.due(now: Date(), lastAttempt: UserDefaults.standard.object(forKey: "backgroundSummaryDate") as? Date,
                             batteryPercent: level, charging: charging, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             thermalSafe: ProcessInfo.processInfo.thermalState == .nominal) else { return false }
            let deadline = Date().addingTimeInterval(10)
            let fetch = PHFetchOptions(); fetch.fetchLimit = 250
            fetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: fetch)
            var count = 0; var screenshots = 0
            for index in 0..<assets.count {
                guard !Task.isCancelled, Date() < deadline, ProcessInfo.processInfo.thermalState == .nominal,
                      !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
                if assets.object(at: index).mediaSubtypes.contains(.photoScreenshot) { screenshots += 1 }
                count += 1
                await Task.yield()
            }
            guard !Task.isCancelled else { return false }
            UserDefaults.standard.set(count, forKey: "backgroundSummaryCount")
            UserDefaults.standard.set(screenshots, forKey: "backgroundScreenshots")
            UserDefaults.standard.set(Date(), forKey: "backgroundSummaryDate")
            return true
        }
        task.expirationHandler = { worker.cancel() }
        Task { let success = await worker.value; task.setTaskCompleted(success: success); schedule() }
    }
}

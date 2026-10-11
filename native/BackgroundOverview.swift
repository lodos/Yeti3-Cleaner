import Foundation
import AppKit
import IOKit.ps

/// A bounded, opt-in local metadata overview. It never creates a deletion plan.
@MainActor final class NativeBackgroundOverview: ObservableObject {
    static let shared = NativeBackgroundOverview()
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "nativeOverview.enabled"); schedule() } }
    @Published var intervalHours: Int { didSet { defaults.set(intervalHours, forKey: "nativeOverview.intervalHours"); schedule() } }
    @Published var requirePower: Bool { didSet { defaults.set(requirePower, forKey: "nativeOverview.requirePower") } }
    @Published var minimumBattery: Int { didSet { defaults.set(minimumBattery, forKey: "nativeOverview.minimumBattery") } }
    @Published private(set) var root: URL?
    @Published private(set) var status = "Выберите папку для короткого обзора. Файлы не удаляются."
    @Published private(set) var busy = false
    @Published private(set) var nextRun: Date?
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var worker: Task<Void, Never>?
    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "nativeOverview.enabled")
        intervalHours = d.object(forKey: "nativeOverview.intervalHours") as? Int ?? 24
        requirePower = d.object(forKey: "nativeOverview.requirePower") as? Bool ?? true
        minimumBattery = d.object(forKey: "nativeOverview.minimumBattery") as? Int ?? 30
        root = d.string(forKey: "nativeOverview.root").map { URL(fileURLWithPath: $0) }
        if let summary = d.string(forKey: "nativeOverview.summary") { status = summary }
        schedule()
    }
    func choose(_ url: URL) {
        stop(); root = url.standardizedFileURL
        defaults.set(root?.path, forKey: "nativeOverview.root"); schedule()
    }
    func stop() { worker?.cancel() }
    func schedule() {
        timer?.invalidate(); timer = nil; nextRun = nil
        guard enabled, root != nil else { if !enabled { stop() }; return }
        let interval = Double(max(6, min(168, intervalHours))) * 3600
        let last = defaults.object(forKey: "nativeOverview.attempt") as? Date ?? Date()
        let next = max(Date().addingTimeInterval(60), last.addingTimeInterval(interval))
        nextRun = next
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.run(automatic: true) }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func run(automatic: Bool = false) {
        guard !busy, let root, !automatic || enabled else { return }
        defaults.set(Date(), forKey: "nativeOverview.attempt")
        guard Self.powerAllowed(requirePower: requirePower, minimumBattery: minimumBattery),
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState == .nominal else {
            status = "Обзор отложен: питание, энергосбережение или нагрев."; schedule(); return
        }
        busy = true; status = "Читаем локальные метаданные…"
        worker = Task(priority: .utility) {
            defer { busy = false; worker = nil; schedule() }
            do {
                let inspection = Task.detached(priority: .utility) { try await Self.overview(root) }
                let summary = try await withTaskCancellationHandler { try await inspection.value } onCancel: { inspection.cancel() }
                try Task.checkCancellation()
                status = summary; defaults.set(summary, forKey: "nativeOverview.summary")
            } catch is CancellationError { status = "Обзор остановлен. Ничего не удалено." }
            catch { status = "Обзор не завершён: \(error.localizedDescription)" }
        }
    }
    nonisolated static func powerAllowed(requirePower: Bool, minimumBattery: Int) -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        if sources.isEmpty { return true } // desktop Mac
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { return false }
            if description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue { return true }
            guard !requirePower, let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { return false }
            return Double(current) / Double(maximum) * 100 >= Double(minimumBattery)
        }
    }
    nonisolated static func overview(_ root: URL, environmentSafe: @Sendable () -> Bool = {
        ProcessInfo.processInfo.thermalState == .nominal && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }, pauseMilliseconds: Int = 20) async throws -> String {
        let volume = try root.resourceValues(forKeys: [.volumeIsLocalKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard volume.volumeIsLocal == true, volume.isDirectory == true, volume.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission)
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) else { throw CocoaError(.fileReadNoPermission) }
        let deadline = Date().addingTimeInterval(10)
        var count = 0; var files = 0; var bytes: Int64 = 0
        while let url = entries.nextObject() as? URL {
            try Task.checkCancellation()
            guard Date() < deadline, environmentSafe() else { throw CancellationError() }
            if count == 250 { break }; count += 1
            if let value = try? url.resourceValues(forKeys: keys), value.isRegularFile == true, value.isSymbolicLink != true,
               value.isUbiquitousItem != true || value.ubiquitousItemDownloadingStatus == .current {
                files += 1; bytes += Int64(value.fileSize ?? 0)
            }
            if pauseMilliseconds > 0 { try await Task.sleep(for: .milliseconds(min(100, pauseMilliseconds))) }
            else { await Task.yield() }
        }
        return "\(Date().formatted()): обзор до 250 объектов верхнего уровня; локальных файлов: \(files), логический размер: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Вложенные папки не анализировались. Ничего не удалено."
    }
}

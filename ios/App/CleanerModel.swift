import SwiftUI
import Photos
import Contacts
import UIKit

@MainActor final class CleanerModel: ObservableObject {
    @Published var photos = PhotoReport()
    @Published var files = FileReport()
    @Published var contacts = ContactReport()
    @Published var roots: [URL] = []
    @Published var selectedPhotos: Set<String> = []
    @Published var selectedFiles: Set<String> = []
    @Published var busy = false
    @Published var status = "Анализ запускается только по вашей команде"
    @Published var message: String?
    @Published var photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var contactAccess = CNContactStore.authorizationStatus(for: .contacts)
    @Published var freeBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var preview: OptimizationPreview?
    @Published var lastScan: Date?
    private var task: Task<Void, Never>?
    let photoService = PhotoService()
    let fileService = FileService()
    let contactService = ContactService()
    init() { refreshAccess() }
    func refreshAccess() {
        photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        contactAccess = CNContactStore.authorizationStatus(for: .contacts)
        // Drop old identifiers when permissions change or the app returns from background.
        if photoAccess != .authorized && photoAccess != .limited { photos = PhotoReport(); selectedPhotos = [] }
        if contactAccess == .denied || contactAccess == .restricted { contacts = ContactReport() }
        let value = try? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        freeBytes = Int64(value?.volumeAvailableCapacity ?? 0); totalBytes = Int64(value?.volumeTotalCapacity ?? 0)
    }
    func scan(_ options: ScanOptions) {
        guard !busy else { return }
        busy = true; selectedPhotos = []; selectedFiles = []; photos = PhotoReport(); files = FileReport(); contacts = ContactReport(); lastScan = nil
        let chosenRoots = roots
        task = Task(priority: .utility) {
            var completed = false
            defer {
                #if !targetEnvironment(macCatalyst)
                if #available(iOS 26, *) { ContinuedAnalysis.shared.finish(success: completed) }
                #endif
                busy = false; task = nil; refreshAccess()
            }
            do {
                var notes: [String] = []
                // Permission sheets must finish before the foreground job is submitted.
                if options.photos { photoAccess = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                if options.contacts && contactAccess == .notDetermined {
                    _ = try? await CNContactStore().requestAccess(for: .contacts)
                    contactAccess = CNContactStore.authorizationStatus(for: .contacts)
                }
                try Task.checkCancellation()
                #if !targetEnvironment(macCatalyst)
                if #available(iOS 26, *), options.continueInBackground {
                    status = "Запуск анализа с системным прогрессом…"
                    let continued = await ContinuedAnalysis.shared.begin { self.cancel() }
                    try Task.checkCancellation()
                    guard continued || UIApplication.shared.applicationState == .active else {
                        throw CleanerError.message("Вернитесь в приложение и повторите запуск анализа.")
                    }
                }
                #endif
                if options.photos {
                    status = "Доступ к медиатеке…"
                    if photoAccess == .authorized || photoAccess == .limited {
                        photos = try await photoService.scan(options: options) { done, total in
                            await MainActor.run { self.status = "Фото и видео: \(done) / \(total)"; self.analysisProgress(Double(done) / Double(max(1, total)) * 0.65) }
                        }
                    } else { notes.append("Нет доступа к фото") }
                }
                try Task.checkCancellation()
                if options.files && !chosenRoots.isEmpty {
                    files = try await fileService.scan(roots: chosenRoots, options: options) { count in
                        await MainActor.run { self.status = "Файлы: \(count)"; self.analysisProgress(0.65 + Double(count) / Double(max(100, options.fileLimit)) * 0.3) }
                    }
                }
                if options.contacts {
                    status = "Анализ контактов…"; analysisProgress(0.95)
                    do {
                        if contactAccess == .notDetermined { _ = try await CNContactStore().requestAccess(for: .contacts) }
                        contactAccess = CNContactStore.authorizationStatus(for: .contacts)
                        if contactsReadable(contactAccess) { contacts = try await contactService.scan(options: options) }
                        else { notes.append("Нет доступа к контактам") }
                    } catch { notes.append("Контакты: \(error.localizedDescription)") }
                }
                try Task.checkCancellation()
                completed = true
                lastScan = Date(); status = notes.isEmpty ? "Анализ завершён. Ничего не удалено." : notes.joined(separator: ". ")
            } catch is CancellationError { status = "Анализ остановлен. Результаты могут быть неполными." }
            catch { status = "Анализ не завершён"; message = error.localizedDescription }
        }
    }
    func automaticScan(settings: SettingsStore) {
        guard !busy else { return }
        refreshAccess()
        UIDevice.current.isBatteryMonitoringEnabled = true
        let device = UIDevice.current
        let level = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
        let charging = device.batteryState == .charging || device.batteryState == .full
        let thermal = ProcessInfo.processInfo.thermalState
        let last = UserDefaults.standard.object(forKey: "automaticScanAttempt") as? Date
        guard settings.automation.due(now: Date(), lastAttempt: last, batteryPercent: level,
            charging: charging, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalSafe: thermal == .nominal || thermal == .fair) else { return }
        var options = settings.options
        options.continueInBackground = false // continued processing requires an explicit user action
        options.photos = options.photos && (photoAccess == .authorized || photoAccess == .limited)
        options.contacts = options.contacts && contactsReadable(contactAccess)
        options.files = options.files && !roots.isEmpty
        guard options.photos || options.contacts || options.files else { return }
        UserDefaults.standard.set(Date(), forKey: "automaticScanAttempt")
        scan(options)
    }
    private func analysisProgress(_ fraction: Double) {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26, *) { ContinuedAnalysis.shared.update(fraction, subtitle: status) }
        #endif
    }
    func photoDryRun() -> CleanupDryRun {
        .make(selected: selectedPhotos, sizes: Dictionary(uniqueKeysWithValues: photos.items.filter { !$0.favorite && !$0.protected && $0.digest != nil }.map { ($0.id, $0.bytes) }), groups: photos.duplicates, scanDate: lastScan)
    }
    func fileDryRun() -> CleanupDryRun {
        .make(selected: selectedFiles, sizes: Dictionary(uniqueKeysWithValues: files.items.map { ($0.id, $0.digest.bytes) }), groups: files.duplicates, scanDate: lastScan)
    }
    func invalidateAnalysis() {
        cancel(); lastScan = nil; selectedPhotos = []; selectedFiles = []
        photos = PhotoReport(); files = FileReport(); contacts = ContactReport()
        status = "Настройки изменились. Повторите анализ."
    }
    func backgrounded() {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26, *), ContinuedAnalysis.shared.isActive { return }
        #endif
        cancel()
    }
    func cancel() { guard task != nil else { return }; task?.cancel(); status = "Остановка после текущего локального ресурса…" }
    func optimize(_ item: PhotoItem, options: ScanOptions) {
        run { self.preview = try await self.photoService.optimize(item, options: options) }
    }
    func savePreview(_ value: OptimizationPreview) {
        run {
            try await self.photoService.save(value)
            self.preview = nil; self.photos = PhotoReport(); self.selectedPhotos = []
            self.message = "Копия сохранена. Оригинал остался в медиатеке. Сейчас копия занимает дополнительное место. Проверьте её в «Фото», прежде чем отдельно решать, нужен ли оригинал."
        }
    }
    func deletePhotos(plan: CleanupDryRun) {
        guard plan.isCurrent(selection: selectedPhotos, scanDate: lastScan) else { message = "Dry run устарел или выбор небезопасен. Повторите анализ и просмотр."; return }
        let selected = photos.items.filter { selectedPhotos.contains($0.id) }; let report = photos
        run {
            try await self.photoService.delete(selected, report: report)
            self.selectedPhotos = []; self.photos = PhotoReport()
            self.message = "Выбранные объекты перемещены в «Недавно удалённые» в Фото. iCloud может синхронизировать удаление. Место может освободиться позже."
        }
    }
    func deleteFiles(plan: CleanupDryRun) {
        guard plan.isCurrent(selection: selectedFiles, scanDate: lastScan) else { message = "Dry run устарел или выбор небезопасен. Повторите анализ и просмотр."; return }
        let selected = files.items.filter { selectedFiles.contains($0.id) }; let report = files
        run {
            let errors = try await self.fileService.delete(selected, report: report)
            self.files = FileReport(); self.selectedFiles = []
            self.message = errors.isEmpty ? "Выбранные файлы удалены. Повторите анализ." : "Часть файлов не удалена:\n" + errors.joined(separator: "\n")
        }
    }
    func clearCache() {
        run {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CleanerPreviews", isDirectory: true)
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            self.preview = nil
            self.message = "Временный просмотр сброшен. Личные данные не изменены."
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        task = Task(priority: .utility) {
            defer { busy = false; task = nil; refreshAccess() }
            do { try await operation() } catch { message = error.localizedDescription }
        }
    }
}

func contactsReadable(_ status: CNAuthorizationStatus) -> Bool {
    if status == .authorized { return true }
    if #available(iOS 18, *) { return status == .limited }
    return false
}

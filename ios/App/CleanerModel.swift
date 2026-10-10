import SwiftUI
import Photos
import Contacts

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
        task = Task {
            defer { busy = false; task = nil; refreshAccess() }
            do {
                var notes: [String] = []
                if options.photos {
                    status = "Доступ к медиатеке…"
                    photoAccess = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                    if photoAccess == .authorized || photoAccess == .limited {
                        photos = try await photoService.scan(options: options) { done, total in
                            await MainActor.run { self.status = "Фото и видео: \(done) / \(total)" }
                        }
                    } else { notes.append("Нет доступа к фото") }
                }
                try Task.checkCancellation()
                if options.files && !chosenRoots.isEmpty {
                    files = try await fileService.scan(roots: chosenRoots) { count in
                        await MainActor.run { self.status = "Файлы: \(count)" }
                    }
                }
                if options.contacts {
                    status = "Анализ контактов…"
                    do {
                        if contactAccess == .notDetermined { _ = try await CNContactStore().requestAccess(for: .contacts) }
                        contactAccess = CNContactStore.authorizationStatus(for: .contacts)
                        if contactsReadable(contactAccess) { contacts = try await contactService.scan() }
                        else { notes.append("Нет доступа к контактам") }
                    } catch { notes.append("Контакты: \(error.localizedDescription)") }
                }
                try Task.checkCancellation()
                lastScan = Date(); status = notes.isEmpty ? "Анализ завершён. Ничего не удалено." : notes.joined(separator: ". ")
            } catch is CancellationError { status = "Анализ остановлен. Результаты могут быть неполными." }
            catch { status = "Анализ не завершён"; message = error.localizedDescription }
        }
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
    func deletePhotos() {
        let selected = photos.items.filter { selectedPhotos.contains($0.id) }; let report = photos
        run {
            try await self.photoService.delete(selected, report: report)
            self.selectedPhotos = []; self.photos = PhotoReport()
            self.message = "Выбранные объекты перемещены в «Недавно удалённые» в Фото. iCloud может синхронизировать удаление. Место может освободиться позже."
        }
    }
    func deleteFiles() {
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
        task = Task {
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

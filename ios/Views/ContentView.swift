import SwiftUI
import Photos
import PhotosUI
import ContactsUI
import UniformTypeIdentifiers
import QuickLook

struct ContentView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            NetworkAdBanner()
            TabView {
            DashboardView().tabItem { Label("Обзор", systemImage: "sparkles") }
            PhotosView().tabItem { Label("Фото", systemImage: "photo.on.rectangle") }
            FilesView().tabItem { Label("Файлы", systemImage: "folder") }
            ContactsView().tabItem { Label("Контакты", systemImage: "person.crop.circle") }
            SettingsView().tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
        }
        }
        .task { model.automaticScan(settings: settings) }
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .background(CleanerIceBackground())
        .alert("YETI³ Cleaner", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("Понятно", role: .cancel) {} } message: { Text(YetiL10n.text(model.message ?? "")) }
        .sheet(item: $model.preview) { preview in OptimizationView(preview: preview) }
        .onChange(of: settings.options) { _, _ in model.invalidateAnalysis() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshAccess(); model.automaticScan(settings: settings); Task { await NetworkPurchase.shared.refresh() } }
            if phase == .background { model.backgrounded(); BackgroundAnalysis.schedule() }
        }
    }
}
struct DashboardView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 56
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 22) {
                CleanerSection {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("YETI³ / CLEANER").font(.caption.monospaced()).tracking(3).foregroundStyle(.cyan)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) {
                                Text("Cleaner.").font(.system(size: titleSize, weight: .bold, design: .rounded)).fixedSize()
                                Spacer(minLength: 0)
                                Image("Mascot").resizable().scaledToFit().frame(width: 88).clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Cleaner.").font(.system(size: titleSize, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                                Image("Mascot").resizable().scaledToFit().frame(width: 72).clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
                            }
                        }
                        Text("Больше места. Всё под контролем.").font(.subheadline).foregroundStyle(.secondary)
                        if model.totalBytes > 0 {
                            ProgressView(value: Double(model.totalBytes-model.freeBytes), total: Double(model.totalBytes)).tint(.cyan)
                            Text("Свободно \(bytesLabel(model.freeBytes)) из \(bytesLabel(model.totalBytes))").font(.subheadline)
                        }
                        Text("Локальный анализ · Очистка без аккаунта").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 14)
                }
                CleanerSection("Стратегия") {
                    Text(settings.strategy.title).font(.headline)
                    Text(YetiL10n.text(settings.strategy.detail)).foregroundStyle(.secondary)
                    Text("Категории и пороги меняются в настройках.").font(.caption)
                }
                CleanerSection {
                    if model.busy { ProgressView(model.status); Button("Остановить анализ", role: .cancel) { model.cancel() } }
                    else { Button { model.scan(settings.options) } label: { Label("Начать анализ", systemImage: "magnifyingglass").font(.headline) }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("startScan") }
                    if !model.busy { Text(YetiL10n.text(model.status)).font(.footnote).foregroundStyle(.secondary) }
                    if let date = model.lastScan { Text("Последний анализ: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                }
                CleanerSection("Результаты") {
                    LabeledContent("Фото и видео", value: "\(model.photos.items.count)")
                    LabeledContent("Группы точных дубликатов", value: "\(model.photos.duplicates.count + model.files.duplicates.count)")
                    LabeledContent("Доступные файлы", value: "\(model.files.items.count)")
                    LabeledContent("Возможные повторы контактов", value: "\(model.contacts.groups.count)")
                }
                CleanerSection("Как освободить место") {
                    Text("Проверьте выбранные объекты перед удалением. Системные кэши и данные других приложений недоступны Cleaner.")
                    #if targetEnvironment(macCatalyst)
                    Text("В macOS: Системные настройки → Основные → Хранилище. Полная Mac-версия Cleaner также анализирует локальные кэши и инструменты разработки.")
                    #else
                    Text("В iOS: Настройки → Основные → Хранилище iPhone / iPad. Там доступны рекомендации Apple и сгрузка приложений.")
                    #endif
                    Text("Для iCloud Фото: Настройки → Фото → Оптимизация хранилища. Сначала убедитесь, что оригиналы синхронизированы.")
                }.font(.footnote)
              }.padding(24).frame(maxWidth: 880)
            }.cleanerScreen().navigationTitle("YETI³ Cleaner").navigationBarTitleDisplayMode(.inline)
        }
    }
}
enum PhotoFilter: String, CaseIterable { case all = "Все", duplicate = "Дубликаты", similar = "Похожие", screenshot = "Скриншоты", video = "Крупные видео" }
struct PhotosView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    @State private var filter: PhotoFilter = .duplicate
    @State private var confirm = false
    var visible: [PhotoItem] {
        let exact = Set(model.photos.duplicates.flatMap { $0 }); let similar = Set(model.photos.similar.flatMap { $0 })
        return model.photos.items.filter { item in
            switch filter {
            case .all: return true
            case .duplicate: return exact.contains(item.id)
            case .similar: return similar.contains(item.id)
            case .screenshot: return settings.options.screenshots && item.screenshot && (item.date ?? .distantFuture) < Date().addingTimeInterval(-Double(settings.options.screenshotDays)*86400)
            case .video: return item.video && item.bytes >= Int64(settings.options.largeVideoMegabytes)*1024*1024 && item.duration >= Double(settings.options.minimumVideoSeconds)
            }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(accessLabel(model.photoAccess)). Анализируются только доступные локальные ресурсы.").font(.footnote)
                    if model.photoAccess == .limited { Button("Изменить выбранные фото") { presentLimitedPhotos() } }
                    if model.photoAccess == .denied || model.photoAccess == .restricted { settingsLink }
                    Picker("Показать", selection: $filter) { ForEach(PhotoFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if model.photos.unavailable > 0 { Text("\(model.photos.unavailable) объектов без локальных оригиналов или с ошибкой чтения. Они не участвуют в точном сравнении и удалении.").font(.caption) }
                    if filter == .similar { Text("Визуальное сходство — предположение. Сравните снимки: они могут быть разными и важными.").font(.caption) }
                }
                if visible.isEmpty { ContentUnavailableView("Нет результатов", systemImage: "photo", description: Text("Запустите анализ и проверьте включённые категории в настройках.")) }
                ForEach(visible) { item in
                    HStack {
                        Button { if model.selectedPhotos.contains(item.id) { model.selectedPhotos.remove(item.id) } else { model.selectedPhotos.insert(item.id) } } label: {
                            Image(systemName: model.selectedPhotos.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2)
                        }.buttonStyle(.borderless).disabled(model.busy || item.favorite || item.protected || item.digest == nil)
                            .accessibilityLabel("Выбрать фото \(item.date?.formatted() ?? "")")
                        NavigationLink {
                            PhotoDetail(item: item)
                        } label: {
                            PhotoThumbnail(id: item.id).frame(width: 60, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Text(item.video ? "Видео · \(Int(item.duration)) сек" : "\(item.width) × \(item.height)")
                                Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? "Без даты").font(.caption)
                                Text(item.digest == nil ? "Оригинал недоступен" : bytesLabel(item.bytes)).font(.caption).foregroundStyle(.secondary)
                                if item.protected { Label("Объект защищён", systemImage: "lock.shield").font(.caption).foregroundStyle(.cyan) }
                                if item.favorite { Label("Избранное защищено", systemImage: "heart.fill").font(.caption).foregroundStyle(.pink) }
                                if let index = model.photos.duplicates.firstIndex(where: { $0.contains(item.id) }) { Text("Дубликаты · группа \(index + 1)").font(.caption).foregroundStyle(.cyan) }
                            }
                        }
                    }
                }
                if !model.selectedPhotos.isEmpty {
                    Section {
                        Text("Выбрано во всех фильтрах: \(model.selectedPhotos.count)")
                        Button("Просмотреть удаление…", role: .destructive) { confirm = true }.disabled(model.busy)
                        Button("Снять выбор") { model.selectedPhotos = [] }.disabled(model.busy)
                    }
                }
            }.cleanerScreen().navigationTitle("Фото и видео")
            .sheet(isPresented: $confirm) {
                DeletionReview(plan: model.photoDryRun(), title: "Dry run · Фото", explanation: "Будут удалены только перечисленные объекты. Изменение синхронизируется через iCloud Фото с другими устройствами. Восстановление обычно доступно в «Недавно удалённых» в течение 30 дней. Размеры логические, освобождение места не гарантируется сразу.", names: model.photos.items.filter { model.selectedPhotos.contains($0.id) }.map { "\($0.date?.formatted() ?? "Без даты") · \(bytesLabel($0.bytes))" }) { plan in model.deletePhotos(plan: plan) }
            }
        }
    }
}
struct PhotoThumbnail: View {
    let id: String
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }
            .task(id: id) { image = await PhotoService.image(id, size: CGSize(width: 800, height: 800)) }
    }
}
struct PhotoDetail: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    let item: PhotoItem
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PhotoThumbnail(id: item.id).frame(maxHeight: 480)
                Text("\(item.width) × \(item.height) · \(bytesLabel(item.bytes))")
                if item.live { Text("Live Photo: фото и движение учитываются вместе.") }
                if item.video { Text("Размер включает доступные ресурсы видео. Воспроизведение и редактирование доступны в приложении «Фото».") }
                if !item.video && !item.live {
                    Button("Предпросмотр оптимизации") { model.optimize(item, options: settings.options) }.buttonStyle(.borderedProminent).disabled(model.busy || item.digest == nil)
                    Text("Будет создан JPEG с уменьшением разрешения и качества. Геопозиция и EXIF не копируются. Оригинал сохраняется.").font(.footnote).foregroundStyle(.secondary)
                }
                if model.busy { ProgressView() }
            }.padding()
        }.cleanerScreen().navigationTitle("Просмотр")
    }
}
struct OptimizationView: View {
    @EnvironmentObject var model: CleanerModel
    @Environment(\.dismiss) var dismiss
    let preview: OptimizationPreview
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image = UIImage(data: preview.data) { Image(uiImage: image).resizable().scaledToFit() }
                    Text("Оригинал: \(bytesLabel(preview.originalBytes))\nКопия: \(bytesLabel(Int64(preview.data.count)))")
                    Text("Потенциальная разница: \(bytesLabel(preview.originalBytes - Int64(preview.data.count)))").font(.headline)
                    Text("Сохранение копии сначала увеличит занятое место. Оригинал не удаляется. Проверьте детали, цвет и качество в «Фото»; удаление оригинала — отдельное решение.")
                    Button("Сохранить копию в Фото") { model.savePreview(preview) }.buttonStyle(.borderedProminent).disabled(model.busy)
                    if model.busy { ProgressView() }
                }.padding()
            }.cleanerScreen().navigationTitle("Оптимизация").toolbar { Button("Закрыть") { dismiss() }.disabled(model.busy) }
        }.interactiveDismissDisabled(model.busy)
    }
}
struct FilesView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    @State private var importer = false
    @State private var confirm = false
    @State private var filter = "Все"
    @State private var previewURL: URL?
    @State private var accessRoot: URL?
    let filters = ["Все", "Дубликаты", "Крупные", "Архивы"]
    var visible: [FileItem] { model.files.items.filter { item in
        switch filter { case "Дубликаты": return item.duplicate; case "Крупные": return item.digest.bytes >= Int64(settings.options.largeMegabytes)*1024*1024; case "Архивы": return item.archive; default: return true }
    } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Выбрать файлы или папку…") { importer = true }.disabled(model.busy)
                    Text("Доступ действует в этой сессии. Облачные файлы, не загруженные на устройство, пропускаются, если провайдер сообщает этот статус.").font(.caption)
                    ForEach(model.roots, id: \.self) { root in Text(root.lastPathComponent).font(.caption) }
                    if !model.roots.isEmpty { Button("Убрать выбранные пути") { model.roots = []; model.files = FileReport(); model.selectedFiles = [] }.disabled(model.busy) }
                    Picker("Показать", selection: $filter) { ForEach(filters, id: \.self) { Text($0) } }
                    if model.files.skipped > 0 { Text("Пропущено: \(model.files.skipped). Нет доступа, облачный ресурс или ссылка.").font(.caption) }
                }
                if visible.isEmpty { ContentUnavailableView("Выберите файлы", systemImage: "folder", description: Text("Затем запустите анализ на вкладке «Обзор». Удаление архивов и больших файлов не считается автоматически безопасным.")) }
                ForEach(visible) { item in
                    HStack {
                        Button { if model.selectedFiles.contains(item.id) { model.selectedFiles.remove(item.id) } else { model.selectedFiles.insert(item.id) } } label: {
                            Image(systemName: model.selectedFiles.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.borderless).disabled(model.busy).accessibilityLabel("Выбрать \(item.url.lastPathComponent)")
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent)
                            Text(item.url.deletingLastPathComponent().lastPathComponent + " · " + bytesLabel(item.digest.bytes)).font(.caption).foregroundStyle(.secondary)
                            if item.duplicate { Text("Точный дубликат").font(.caption).foregroundStyle(.cyan) }
                        }
                        Spacer()
                        Button { if item.root.startAccessingSecurityScopedResource() { accessRoot = item.root }; previewURL = item.url } label: { Image(systemName: "eye") }.buttonStyle(.borderless).accessibilityLabel("Просмотреть \(item.url.lastPathComponent)")
                    }
                }
                if !model.selectedFiles.isEmpty {
                    Button("Просмотреть удаление: \(model.selectedFiles.count)…", role: .destructive) { confirm = true }.disabled(model.busy)
                    Button("Снять выбор") { model.selectedFiles = [] }.disabled(model.busy)
                }
            }.cleanerScreen().navigationTitle("Доступные файлы")
            .fileImporter(isPresented: $importer, allowedContentTypes: [.folder, .item], allowsMultipleSelection: true) { result in
                do { model.roots = Array(Set(model.roots + (try result.get()))); model.files = FileReport(); model.selectedFiles = [] }
                catch { model.message = error.localizedDescription }
            }
            .quickLookPreview($previewURL)
            .onChange(of: previewURL) { _, value in if value == nil { accessRoot?.stopAccessingSecurityScopedResource(); accessRoot = nil } }
            .sheet(isPresented: $confirm) {
                DeletionReview(plan: model.fileDryRun(), title: "Dry run · Файлы", explanation: "Удаление может быть необратимым: наличие корзины зависит от провайдера. Изменения в облачной папке могут синхронизироваться на другие устройства. Сделайте резервную копию. Изменённые после анализа файлы будут пропущены.", names: model.files.items.filter { model.selectedFiles.contains($0.id) }.map { $0.url.lastPathComponent + " · " + bytesLabel($0.digest.bytes) }) { plan in model.deleteFiles(plan: plan) }
            }
        }
    }
}
struct DeletionReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: CleanupDryRun
    let title: String
    let explanation: String
    let names: [String]
    let action: (CleanupDryRun) -> Void
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            List {
                Section("Предварительный план · ничего не удалено") {
                    Text(explanation)
                    LabeledContent("Логический размер", value: bytesLabel(plan.estimatedBytes))
                    Text("План действует 15 минут. Перед выполнением содержимое проверяется повторно.").font(.caption)
                    if !plan.allowed { Text("Удаление заблокировано: оставьте минимум один экземпляр каждого дубликата и повторите анализ.").foregroundStyle(.red) }
                }
                Section("Будет удалено: \(names.count)") { ForEach(Array(names.enumerated()), id: \.offset) { _, name in Text(name) } }
                Section {
                    Toggle("Я проверил список и подтверждаю удаление", isOn: $acknowledged)
                    Button("Удалить выбранное", role: .destructive) { dismiss(); action(plan) }.disabled(!acknowledged || names.isEmpty || !plan.allowed)
                }
            }.navigationTitle(title).toolbar { Button("Отмена") { dismiss() } }
        }
    }
}
struct ContactsView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var settings: SettingsStore
    @State private var selected: ContactItem?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Анализируются только разрешённые контакты. Совпадение телефона или email — повод проверить записи, а не доказательство дубликата.")
                    Text("Cleaner не объединяет и не удаляет контакты автоматически. Откройте запись для просмотра и редактирования в системном интерфейсе.")
                    if model.contactAccess == .denied || model.contactAccess == .restricted { settingsLink }
                    if #available(iOS 18, *), model.contactAccess == .limited { Text("Доступ ограничен. Изменить список разрешённых контактов можно в Настройках iOS."); settingsLink }
                }.font(.footnote)
                ForEach(Array(model.contacts.groups.enumerated()), id: \.offset) { index, ids in
                    Section("Возможные повторы · \(index + 1)") {
                        ForEach(model.contacts.items.filter { ids.contains($0.id) }) { item in contactRow(item) }
                    }
                }
                if settings.options.showIncompleteContacts { Section("Неполные записи") { ForEach(model.contacts.items.filter(\.incomplete)) { item in contactRow(item) } } }
                if model.contacts.items.isEmpty { ContentUnavailableView("Нет результатов", systemImage: "person.crop.circle", description: Text("Включите анализ контактов в настройках и запустите сканирование.")) }
            }.cleanerScreen().navigationTitle("Контакты")
            .sheet(item: $selected, onDismiss: { model.contacts = ContactReport() }) { item in ContactEditor(identifier: item.id) }
        }
    }
    func contactRow(_ item: ContactItem) -> some View {
        Button { selected = item } label: {
            VStack(alignment: .leading) {
                Text(item.name.isEmpty ? "Без имени" : item.name)
                Text((item.phones + item.emails).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(model.busy)
    }
}
struct ContactEditor: UIViewControllerRepresentable {
    let identifier: String
    func makeUIViewController(context: Context) -> UINavigationController {
        do {
            let contact = try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactViewController.descriptorForRequiredKeys()])
            let controller = CNContactViewController(for: contact); controller.allowsEditing = true; controller.allowsActions = false
            return UINavigationController(rootViewController: controller)
        } catch {
            let controller = UIViewController(); let label = UILabel(); label.text = "Контакт недоступен. Закройте окно и повторите анализ."; label.numberOfLines = 0
            controller.view = label; return UINavigationController(rootViewController: controller)
        }
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
var settingsLink: some View { Button("Открыть настройки доступа") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
func accessLabel(_ status: PHAuthorizationStatus) -> String {
    switch status { case .authorized: return "Полный доступ"; case .limited: return "Доступ к выбранным фото"; case .denied: return "Доступ запрещён"; case .restricted: return "Доступ ограничен системой"; default: return "Разрешение ещё не запрошено" }
}
@MainActor func presentLimitedPhotos() {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
}

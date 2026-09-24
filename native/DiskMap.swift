import SwiftUI
import AppKit
import CryptoKit

private let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Yeti3-Cleaner")
private let releaseVersion = Bundle.main.object(forInfoDictionaryKey: "YetiReleaseVersion") as? String ?? "0.4.1-rc.3"
private let minimumMacOS = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "14.0"
private let cyan = Color(red: 0.2, green: 0.85, blue: 0.95)
private func human(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

@MainActor final class DiskModel: ObservableObject {
    @Published var root = FileManager.default.homeDirectoryForCurrentUser
    @Published var entries: [Entry] = []
    @Published var selected: Entry?
    @Published var cacheStatus = ""
    @Published var busy = false
    @Published var status = "Выберите диск или папку. Сканирование ничего не удаляет."
    @Published var error: String?
    @Published var include: [String] = []
    @Published var exclude: [String] = []
    @Published var preview = ""
    @Published var previewBusy = false
    @Published var updateStatus = "Проверка только по запросу. Данные о файлах не отправляются."
    @Published var includePrerelease = releaseVersion.contains("-rc.")
    @Published var updateBusy = false
    @Published var pendingUpdate: UpdateInfo?
    private var token = Cancellation()
    var total: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    var engine: URL { Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MacOS/yeti3-cleaner-engine") }
    init() { reloadRules() }
    @discardableResult func reloadRules() -> Bool {
        do {
            let p = support.appendingPathComponent("folders.json")
            if !FileManager.default.fileExists(atPath: p.path) { include = []; exclude = []; return true }
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: p)) as? [String: [String]]
            guard let data else { throw CocoaError(.fileReadCorruptFile) }
            include = data["include"] ?? []; exclude = data["exclude"] ?? []; return true
        } catch { self.error = "Не удалось прочитать правила: \(error.localizedDescription)"; return false }
    }
    func saveRules(_ additions: [String], _ exclusions: [String]) {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["include": additions, "exclude": exclusions], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: support.appendingPathComponent("folders.json"), options: .atomic)
            include = additions; exclude = exclusions
        } catch { self.error = "Настройки не сохранены: \(error.localizedDescription)" }
    }
    func add(_ url: URL, excluded: Bool) {
        guard reloadRules() else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if excluded { saveRules(include, Array(Set(exclude + [path])).sorted()); return }
        do {
            let p = Process(); p.executableURL = engine; p.arguments = ["check-folder", path]
            let pipe = Pipe(); p.standardError = pipe; try p.run()
            let message = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { self.error = String(decoding: message, as: UTF8.self); return }
            saveRules(Array(Set(include + [path])).sorted(), exclude)
        } catch { self.error = error.localizedDescription }
    }
    func replacePreset(_ old: String, with url: URL) {
        guard reloadRules() else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path != old else { return }
        if path.hasPrefix(old + "/") || old.hasPrefix(path + "/") || exclude.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) {
            error = "Выбранная папка пересекается с исключением или прежним каталогом. Выберите отдельную папку: исключённые данные не включаются в очистку."; return
        }
        do {
            let process = Process(); process.executableURL = engine; process.arguments = ["check-folder", path]
            let pipe = Pipe(); process.standardError = pipe; try process.run()
            let message = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { self.error = String(decoding: message, as: UTF8.self); return }
            let alert = NSAlert(); alert.messageText = "Заменить каталог пресета?"; alert.informativeText = "Исключить: " + old + "\nОчищать содержимое: " + path + "\nНовое правило применяется при следующей очистке, без ограничения возраста файлов."; alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: "Заменить")
            if alert.runModal() == .alertSecondButtonReturn { saveRules(Array(Set(include + [path])).sorted(), Array(Set(exclude + [old])).sorted()) }
        } catch { self.error = error.localizedDescription }
    }
    func choose(_ action: (URL) -> Void) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "Выбрать папку"
        if panel.runModal() == .OK, let url = panel.url { action(url) }
    }
    func start(_ url: URL) {
        token.cancel(); let cancellation = Cancellation(); token = cancellation
        root = url; entries = []; selected = nil; busy = true; status = "Читаем сохранённый снимок…"; cacheStatus = ""
        UserDefaults.standard.set(url.path, forKey: "lastDiskMapRoot")
        let executable = engine
        let started = Date()
        let live = LiveScan { entries, count in
            guard !cancellation.cancelled, self.busy else { return }
            self.entries = entries
            self.status = "Просмотрено объектов: \(count.formatted()) · размеры ещё уточняются"
            if self.cacheStatus.hasPrefix("Снимок от") { self.cacheStatus = "Показываем текущее сканирование · размеры неполные" }
        }
        DispatchQueue.global(qos: .utility).async {
            var cache: DiskCache?
            do {
                // The engine owns migration of the old history database. Do this before
                // SQLite creates any cache table, otherwise an empty new DB could mask history.
                let p = Process(); p.executableURL = executable; p.arguments = ["history-path"]
                let output = Pipe(); let errors = Pipe(); p.standardOutput = output; p.standardError = errors
                try p.run()
                let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    throw NSError(domain: "Yeti3", code: 5, userInfo: [NSLocalizedDescriptionKey: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)])
                }
                cache = try DiskCache(path: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                if let saved = try cache?.load(url) {
                    DispatchQueue.main.async {
                        guard !cancellation.cancelled else { return }
                        self.entries = saved.entries
                        self.cacheStatus = "Снимок от \(saved.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(saved.complete ? "обход завершён" : "неполный") · обновляем…"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard !cancellation.cancelled else { return }
                    self.cacheStatus = "Кэш недоступен: \(error.localizedDescription)"
                }
            }
            guard !cancellation.cancelled else { return }
            var lastSave = Date.distantPast
            func persist(_ entries: [Entry], complete: Bool) {
                guard let cache else { return }
                do { try cache.save(url, entries: entries, started: started, complete: complete) }
                catch {
                    DispatchQueue.main.async {
                        guard !cancellation.cancelled else { return }
                        self.cacheStatus = "Снимок не сохранён: \(error.localizedDescription)"
                    }
                }
            }
            let result = Result { try scan(url, token: cancellation, progress: { _ in }, entryProgress: { entry, count in
                guard !cancellation.cancelled else { return }
                live.receive(entry, count: count)
                // Only disk persistence is rate limited. UI delivery is immediate.
                if Date().timeIntervalSince(lastSave) >= 2 {
                    persist(live.snapshot(), complete: false); lastSave = Date()
                }
            }) }
            if case .success(let entries) = result, !entries.isEmpty || !cancellation.cancelled {
                persist(entries, complete: !cancellation.cancelled && entries.allSatisfy { $0.errors == 0 })
            }
            DispatchQueue.main.async {
                guard !cancellation.cancelled else { return }
                self.busy = false
                switch result {
                case .success(let entries):
                    self.entries = entries
                    if !self.cacheStatus.contains("недоступен") && !self.cacheStatus.contains("не сохранён") {
                        self.cacheStatus = "Снимок сохранён · \(Date().formatted(date: .abbreviated, time: .shortened))"
                    }
                    let errors = entries.reduce(0) { $0 + $1.errors }
                    self.status = errors == 0 ? "Сканирование завершено · \(entries.count) объектов" : "Неполный результат: пропущено \(errors) недоступных объектов. Проверьте доступ к диску в настройках macOS."
                case .failure(let error): self.status = "Папка недоступна · сохранённый снимок может быть устаревшим"; self.error = error.localizedDescription
                }
            }
        }
    }
    func cancel() { token.cancel(); busy = false; cacheStatus = cacheStatus.replacingOccurrences(of: " · обновляем…", with: " · сохранённый результат"); status = "Остановлено · показана только прочитанная часть диска. Размеры неполные." }
    func showPreview() {
        guard !previewBusy else { return }; previewBusy = true; preview = "Подготавливаем список…"
        let executable = engine
        DispatchQueue.global(qos: .utility).async {
            do {
                let p = Process(); p.executableURL = executable; p.arguments = ["clean", "--max", "--dry-run"]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { self.preview = text; self.previewBusy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.previewBusy = false } }
        }
    }
    func checkUpdate() {
        guard !updateBusy else { return }; updateBusy = true; pendingUpdate = nil; updateStatus = "Проверяем последнюю версию…"
        Task {
            defer { updateBusy = false }
            do {
                let channel = includePrerelease ? "latest-prerelease.json" : "latest.json"
                let url = URL(string: "https://raw.githubusercontent.com/lodos/Yeti3-Cleaner/master/downloads/" + channel)!
                var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let current = releaseVersion
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let release = try validateUpdate(data, osVersion: "\(os.majorVersion).\(os.minorVersion)", allowPrerelease: includePrerelease)
                if let next = ReleaseVersion(release.version), let installed = ReleaseVersion(current), next > installed {
                    pendingUpdate = release; updateStatus = "Доступна \(release.version)\(release.prerelease == true ? " · ПРЕДРЕЛИЗ" : "") · macOS \(release.minimum_macos)+"
                } else { updateStatus = "Установлена последняя версия: \(current)" }
            } catch { updateStatus = "Не удалось проверить обновление: \(error.localizedDescription). Можно повторить позже." }
        }
    }
    func downloadUpdate() {
        guard let release = pendingUpdate, !updateBusy else { return }
        updateBusy = true; updateStatus = "Загружаем обновление и проверяем SHA-256…"
        Task {
            defer { updateBusy = false }
            do {
                let (temp, response) = try await URLSession.shared.download(from: release.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let data = try Data(contentsOf: temp)
                try verifyUpdate(data, sha256: release.sha256)
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dmg")
                try data.write(to: destination, options: .atomic)
                NSWorkspace.shared.open(destination)
                updateStatus = "Образ проверен и открыт. Завершите Cleaner, затем перенесите новую версию в «Программы» с заменой. Настройки сохранятся."
            } catch { updateStatus = "Обновление не установлено: \(error.localizedDescription)" }
        }
    }
}

struct Ray: Shape {
    let index: Int; let count: Int; let fraction: Double
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let inner = min(rect.width, rect.height) * 0.17
        let outer = inner + min(rect.width, rect.height) * 0.30 * fraction
        let step = 360.0 / Double(max(count, 1)); let gap = min(1.0, step * 0.12)
        let start = Angle.degrees(Double(index) * step - 90 + gap)
        let end = Angle.degrees(Double(index + 1) * step - 90 - gap)
        var p = Path(); p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true); p.closeSubpath(); return p
    }
}
struct DiskView: View {
    @StateObject private var model = DiskModel()
    @State private var tab = 0
    @State private var filter = ""
    @State private var showPreview = false
    private var shown: [Entry] { model.entries.filter { filter.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(filter) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "sun.max.fill").font(.system(size: 31)).foregroundStyle(cyan)
                VStack(alignment: .leading) { Text("YETI³ · Карта диска · Предрелиз").font(.title2.bold()); Text("Посмотрите, что занимает место. Решайте, что очищать.").foregroundStyle(.secondary) }
                Spacer()
                Picker("Раздел", selection: $tab) { Text("Обзор").tag(0); Text("Настройки").tag(1); Text("Обновление").tag(2) }.pickerStyle(.segmented).frame(width: 320)
            }
            Divider()
            if tab == 0 { mapView } else if tab == 1 { ScrollView { VStack(alignment: .leading, spacing: 24) { SettingsPanel(model: model); rulesView } } } else { updateView }
            Spacer(minLength: 0)
        }
        .padding(24).frame(minWidth: 1000, minHeight: 720)
        .background(LinearGradient(colors: [Color(red: 0.025, green: 0.075, blue: 0.12), Color(red: 0.015, green: 0.025, blue: 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark).tint(cyan)
        .alert("YETI³ Cleaner", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("Понятно", role: .cancel) {} } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showPreview) {
            VStack(alignment: .leading) {
                Text("Предпросмотр очистки").font(.title2.bold())
                Text("Это только список действий. Файлы не удаляются.").foregroundStyle(.secondary)
                ScrollView { Text(model.preview).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Закрыть") { showPreview = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 820, height: 560)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
            if let i = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.count > i + 1 { model.start(URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
            else if !CommandLine.arguments.contains("--updates") && !CommandLine.arguments.contains("--settings") {
                let path = UserDefaults.standard.string(forKey: "lastDiskMapRoot") ?? FileManager.default.homeDirectoryForCurrentUser.path
                model.start(URL(fileURLWithPath: path))
            }
            if CommandLine.arguments.contains("--updates") { tab = 2; model.checkUpdate() }
            if CommandLine.arguments.contains("--settings") { tab = 1 }
        }
    }
    private var mapView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.start(URL(fileURLWithPath: "/")) } label: { Label("Весь Mac", systemImage: "internaldrive") }
                Button("Домашняя папка") { model.start(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Выбрать папку / диск…") { model.choose { model.start($0) } }
                Button { model.start(model.root.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }.disabled(model.root.path == "/")
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("Остановить") { model.cancel() } }
                else { Button { model.start(model.root) } label: { Label("Сканировать", systemImage: "arrow.clockwise") } }
            }
            if !model.cacheStatus.isEmpty { Text(model.cacheStatus).font(.caption).foregroundStyle(.secondary) }
            Text(model.root.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(cyan.opacity(0.1), lineWidth: 1).padding(10)
                        ForEach(Array(model.entries.prefix(180).enumerated()), id: \.element.id) { i, entry in
                            Ray(index: i, count: min(model.entries.count, 180), fraction: Double(entry.bytes) / Double(max(model.entries.first?.bytes ?? 1, 1)))
                                .fill(Color(hue: 0.48 + Double(i % 15) * 0.018, saturation: 0.6, brightness: model.selected?.id == entry.id ? 1 : 0.72))
                                .overlay(Ray(index: i, count: min(model.entries.count, 180), fraction: Double(entry.bytes) / Double(max(model.entries.first?.bytes ?? 1, 1))).stroke(model.selected?.id == entry.id ? Color.white : Color.clear, lineWidth: 2))
                                .contentShape(Ray(index: i, count: min(model.entries.count, 180), fraction: Double(entry.bytes) / Double(max(model.entries.first?.bytes ?? 1, 1))))
                                .onTapGesture { model.selected = entry; if entry.directory { model.start(entry.url) } }
                                .help("\(entry.url.lastPathComponent) · \(human(entry.bytes))\(entry.directory ? " · Открыть папку" : "")")
                                .accessibilityLabel("\(entry.url.lastPathComponent), \(human(entry.bytes))")
                        }
                        VStack(spacing: 8) {
                            if model.busy { ProgressView().controlSize(.regular) }
                            Text(human(model.total)).font(.title2.bold())
                            Text(model.busy ? "Читаем диск…" : "найдено").foregroundStyle(.secondary).font(.caption)
                        }
                    }.frame(width: 410, height: 410)
                    Text("Чем больше размер — тем длиннее луч.\nНажмите каталог, чтобы увидеть его содержимое.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if model.entries.count > 180 { Text("На диаграмме 180 крупнейших объектов. Полный список справа.").font(.caption).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading) {
                    TextField("Найти в этой папке", text: $filter).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(shown) { entry in
                                HStack {
                                    Button { model.selected = entry } label: {
                                        HStack { Image(systemName: entry.directory ? "folder.fill" : "doc").foregroundStyle(cyan); Text(entry.url.lastPathComponent).lineLimit(1).truncationMode(.middle); Spacer(); Text(human(entry.bytes)).monospacedDigit(); if entry.errors > 0 { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) } }
                                        .padding(9).background(model.selected?.id == entry.id ? cyan.opacity(0.17) : Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                    if entry.directory { Button { model.start(entry.url); filter = "" } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).help("Открыть каталог") }
                                }
                            }
                        }
                    }.frame(height: 335)
                    if let entry = model.selected {
                        Text(entry.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        HStack {
                            Button("В Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                            Button("Исключить") { model.add(entry.url, excluded: true) }
                            if entry.directory { Button("В очистку…") {
                                let alert = NSAlert(); alert.messageText = "Добавить папку в очистку?"; alert.informativeText = "Все содержимое \(entry.url.path) будет включено в следующие запуски очистки. Сама папка останется. Проверьте предпросмотр перед запуском."; alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: "Добавить")
                                if alert.runModal() == .alertSecondButtonReturn { model.add(entry.url, excluded: false) }
                            } }
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            Text(model.status).font(.callout).foregroundStyle(model.status.contains("Неполный") ? .orange : .secondary)
            Text("Размеры файлов, а не физически освобождаемое место. Снимки APFS, клоны и закрытые каталоги могут давать расхождение. Ссылки и вложенные тома пропускаются; другой диск выберите отдельно.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var rulesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ваш набор каталогов").font(.title.bold())
            Text("Текущие пресеты сохранены. Дополните их своими папками или исключите то, что нельзя трогать. Исключение имеет приоритет; если оно внутри папки, эта папка целиком пропускается при очистке.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                ruleList("Дополнительно очищать", paths: model.include, excluded: false)
                ruleList("Никогда не трогать", paths: model.exclude, excluded: true)
            }
            Label("Документы, проекты, фото, системные папки и профили браузеров защищены. Добавление папки ничего не удаляет.", systemImage: "lock.shield").font(.callout).foregroundStyle(cyan)
            Text("Safari: очищается только кэш. Cleaner не удаляет историю, cookies, пароли и базы сессий. Состояние вкладок и проигрывателя зависит также от браузера и сайта.").font(.callout).foregroundStyle(.secondary)
            Button("Показать план очистки…") { showPreview = true; model.showPreview() }.disabled(model.previewBusy)

        }.onAppear { model.reloadRules() }
    }
    private func ruleList(_ title: String, paths: [String], excluded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if paths.isEmpty { Text(excluded ? "Дополнительных исключений нет" : "Используются только пресеты").foregroundStyle(.secondary) }
                    ForEach(paths, id: \.self) { path in
                        HStack { Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Spacer(); Button { guard model.reloadRules() else { return }; model.saveRules(excluded ? model.include : model.include.filter { $0 != path }, excluded ? model.exclude.filter { $0 != path } : model.exclude) } label: { Image(systemName: "minus.circle") }.help("Убрать правило; файлы останутся") }
                    }
                }
            }.frame(height: 240)
            Button(excluded ? "Добавить исключение…" : "Добавить папку…") { model.choose { url in
                if excluded { model.add(url, excluded: true) } else {
                    let alert = NSAlert(); alert.messageText = "Очищать содержимое этой папки?"; alert.informativeText = url.path + "\nПравило применяется при следующем запуске очистки. Используйте предпросмотр."; alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: "Добавить")
                    if alert.runModal() == .alertSecondButtonReturn { model.add(url, excluded: false) }
                }
            } }
        }.padding(18).frame(maxWidth: .infinity).background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var updateView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Обновление YETI³ Cleaner", systemImage: "arrow.down.circle").font(.title.bold())
            Text("Предрелиз \(releaseVersion) · Intel + Apple Silicon · macOS \(minimumMacOS)+").foregroundStyle(.secondary)
            Toggle("Получать предварительные версии", isOn: $model.includePrerelease).onChange(of: model.includePrerelease) { _ in model.pendingUpdate = nil }
            Text(model.updateStatus).textSelection(.enabled)
            HStack {
                Button("Проверить обновление") { model.checkUpdate() }.disabled(model.updateBusy)
                if model.pendingUpdate != nil { Button("Скачать и открыть установщик") { model.downloadUpdate() }.disabled(model.updateBusy) }
                if model.updateBusy { ProgressView().controlSize(.small) }
            }
            Text("Источник — публичный репозиторий lodos/Yeti3-Cleaner. Перед открытием образа проверяется SHA-256. Замена приложения выполняется вами через Finder. Настройки и история хранятся отдельно от приложения.").foregroundStyle(.secondary)
        }
    }
}
@main struct DiskMapApp: App {
    var body: some Scene { WindowGroup("YETI³ · Карта диска") { DiskView() } }
}

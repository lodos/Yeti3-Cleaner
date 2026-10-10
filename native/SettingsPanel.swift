import SwiftUI
import AppKit

@MainActor final class SettingsStore: ObservableObject {
    @Published var values: [String: [String: Any]] = [:]
    @Published var presets: [[String: Any]] = []
    @Published var failure: String?
    @Published var loading = false
    private var defaults: [String: [String: Any]] = [:]
    private var path: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Yeti3-Cleaner/settings.json") }
    func load(_ engine: URL) {
        guard !loading else { return }; loading = true
        DispatchQueue.global(qos: .utility).async {
            do {
                let process = Process(); process.executableURL = engine; process.arguments = ["settings-data"]
                let pipe = Pipe(); process.standardOutput = pipe
                try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                guard process.terminationStatus == 0, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let settings = object["settings"] as? [String: [String: Any]],
                      let defaults = object["defaults"] as? [String: [String: Any]],
                      let presets = object["presets"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
                DispatchQueue.main.async { self.values = settings; self.defaults = defaults; self.presets = presets; self.loading = false }
            } catch { DispatchQueue.main.async { self.failure = error.localizedDescription; self.loading = false } }
        }
    }
    func set(_ group: String, _ key: String, _ value: Any) {
        do {
            guard var latest = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: [String: Any]], latest[group]?[key] != nil else { throw CocoaError(.fileReadCorruptFile) }
            latest[group]?[key] = value
            try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
            values = latest
        } catch { failure = "Настройки не сохранены: \(error.localizedDescription)" }
    }
    func reset() -> Bool {
        do {
            guard !defaults.isEmpty else { return false }
            try JSONSerialization.data(withJSONObject: defaults, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
            values = defaults; return true
        } catch { failure = error.localizedDescription; return false }
    }
}

struct SettingsPanel: View {
    @ObservedObject var model: DiskModel
    @StateObject private var store = SettingsStore()
    private let groups = [
        ("macos", "macOS", ["trash", "application_caches", "logs", "crash_reports"]),
        ("browsers", "Кэши браузеров", ["safari", "chrome", "opera", "firefox", "chromium", "brave", "arc"]),
        ("development", "Разработка", ["xcode_derived_data", "xcode_source_packages", "unavailable_simulators", "cargo", "npm", "npx", "pnpm", "yarn", "pip", "uv", "gradle", "cocoapods"]),
        ("ai_ml", "Модели", ["coreml"]),
        ("homebrew", "Homebrew", ["enabled", "autoremove", "old_versions", "cache", "temporary_builds"]),
        ("docker", "Docker", ["enabled", "build_cache", "unused_images", "stopped_containers", "unused_networks"]),
        ("mobile", "iPhone и iPad", ["delete_all_local_backups"]),
        ("behavior", "Интерфейс", ["show_reclaimed_space"])
    ]
    private let names = ["trash":"Корзина", "application_caches":"Кэши приложений", "logs":"Журналы", "crash_reports":"Отчёты о сбоях", "xcode_derived_data":"Xcode DerivedData", "xcode_source_packages":"Пакеты Xcode", "unavailable_simulators":"Недоступные симуляторы", "coreml":"Кэш CoreML", "enabled":"Включить", "autoremove":"Неиспользуемые зависимости", "old_versions":"Старые версии", "cache":"Кэш", "temporary_builds":"Временные сборки", "build_cache":"Кэш сборок", "unused_images":"Неиспользуемые образы", "stopped_containers":"Остановленные контейнеры", "unused_networks":"Неиспользуемые сети", "delete_all_local_backups":"Удалять локальные резервные копии iPhone/iPad", "show_reclaimed_space":"Показывать освобождённое место"]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Настройки очистки").font(.title.bold())
            Text("Изменения сохраняются сразу. Текущий набор — исходный пресет; переключатели, возраст файлов и каталоги можно изменить.").foregroundStyle(.secondary)
            if store.loading { ProgressView("Загружаем настройки…") }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.0) { group, title, keys in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(YetiL10n.text(title)).font(.headline)
                        ForEach(keys, id: \.self) { key in
                            Toggle(YetiL10n.text(names[key] ?? key.capitalized), isOn: Binding(get: { store.values[group]?[key] as? Bool ?? false }, set: { store.set(group, key, $0) }))
                        }
                        if group == "macos" { age("Журналы старше", group: group, key: "logs_min_age_days") }
                        if group == "development" {
                            age("Пакеты Xcode старше", group: group, key: "xcode_source_packages_min_age_days")
                            age("Кэш Gradle старше", group: group, key: "gradle_min_age_days")
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.disabled(store.values.isEmpty)
            Text("Временные файлы, Podman и остальные кэши моделей ещё не подключены к движку. Docker volumes и пользовательские документы защищены.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Каталоги исходного пресета").font(.title2.bold())
            Text("Выключите путь или замените его своей папкой. Переключатели категорий выше также учитываются; отключённая категория не очищается. Возраст файлов для заменённой папки: без ограничения.").font(.callout).foregroundStyle(.secondary)
            ForEach(store.presets.indices, id: \.self) { index in
                if let path = store.presets[index]["path"] as? String {
                    HStack {
                        Toggle(YetiL10n.text(isOn: Binding(get: { !model.exclude.contains { path == $0 || path.hasPrefix($0 + "/") } }, set: { enabled in
                            guard model.reloadRules() else { return }
                            if enabled {
                                if model.exclude.contains(where: { path.hasPrefix($0 + "/") }) { model.error = "Путь находится внутри исключённой папки. Сначала измените это исключение ниже."; return }
                                model.saveRules(model.include, model.exclude.filter { $0 != path })
                            } else { model.saveRules(model.include, Array(Set(model.exclude + [path])).sorted()) }
                        }))) { Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                        Button("Заменить…") { model.choose { model.replacePreset(path, with: $0) } }
                    }.padding(8).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Button("Восстановить исходный пресет…") {
                let alert = NSAlert(); alert.messageText = YetiL10n.text("Восстановить исходный набор?"); alert.informativeText = YetiL10n.text("Категории и сроки вернутся к исходным значениям. Добавленные папки и исключения будут убраны из настроек. Файлы не удаляются."); alert.addButton(withTitle: YetiL10n.text("Отмена")); alert.addButton(withTitle: YetiL10n.text("Восстановить"))
                if alert.runModal() == .alertSecondButtonReturn, store.reset() { model.saveRules([], []) }
            }.disabled(store.values.isEmpty)
        }
        .onAppear { store.load(model.engine); model.reloadRules() }
        .alert("Настройки", isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })) { Button("Понятно") {} } message: { Text(store.failure ?? "") }
    }
    private func age(_ title: String, group: String, key: String) -> some View {
        HStack {
            Text(YetiL10n.text(title)); Spacer()
            TextField("Дни", value: Binding(get: { store.values[group]?[key] as? Int ?? 0 }, set: { store.set(group, key, max(0, min($0, 36500))) }), format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).foregroundStyle(.primary).font(.system(size: 15, weight: .semibold, design: .monospaced)).frame(width: 88).environment(\.colorScheme, .dark)
            Text("дней")
        }
    }
}

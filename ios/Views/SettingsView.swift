import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var model: CleanerModel
    @State private var cacheConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Стратегия очистки") {
                    Picker("Режим", selection: $settings.strategy) { ForEach(Strategy.allCases) { Text(YetiL10n.text($0.title)).tag($0) } }.accessibilityIdentifier("strategyPicker")
                    Text(YetiL10n.text(settings.strategy.detail)).font(.footnote)
                    Text("Настройки сохраняются отдельно для каждой стратегии. Личные данные удаляются только после dry run и подтверждения.").font(.caption)
                }
                Section("Автоматический dry run") {
                    Toggle("Анализировать при открытии приложения", isOn: $settings.automation.enabled)
                    Picker("Не чаще", selection: $settings.automation.intervalHours) {
                        Text("Каждые 6 часов").tag(6); Text("Раз в день").tag(24); Text("Раз в неделю").tag(168)
                    }
                    Toggle("Только на зарядке", isOn: $settings.automation.requireCharging)
                    Stepper("Заряд не ниже \(settings.automation.minimumBatteryPercent)%", value: $settings.automation.minimumBatteryPercent, in: 20...90, step: 10)
                    Text("Без запросов новых разрешений и удаления. При энергосбережении и перегреве анализ откладывается. iOS не гарантирует запуск по расписанию в закрытом приложении. Фото и файлы выбираете вы; контакты изменяются только вручную.").font(.caption)
                }
                Section("Локальное сканирование") {
                    Toggle("Фото и видео", isOn: option(\.photos))
                    Toggle("Похожие фото", isOn: option(\.similar)).disabled(!settings.options.photos)
                    Toggle("Старые скриншоты", isOn: option(\.screenshots)).disabled(!settings.options.photos)
                    Toggle("Выбранные файлы", isOn: option(\.files))
                    Toggle("Контакты", isOn: option(\.contacts))
                    Stepper("Скриншоты старше \(settings.options.screenshotDays) дней", value: option(\.screenshotDays), in: 7...730, step: 7)
                    Stepper("Крупные объекты от \(settings.options.largeMegabytes) МБ", value: option(\.largeMegabytes), in: 10...2000, step: 10)
                }
                Section("Копия фотографии") {
                    Slider(value: option(\.jpegQuality), in: 0.6...0.95, step: 0.05) { Text("Качество JPEG") }
                    Text("Качество JPEG: \(Int(settings.options.jpegQuality * 100))%")
                    Picker("Длинная сторона", selection: option(\.maxPixel)) { Text("2048 px").tag(2048); Text("2560 px").tag(2560); Text("4096 px").tag(4096) }
                    Text("Оригинал сохраняется. Копия не содержит геопозиции и EXIF. RAW, HDR, Live Photo, панорамы и отредактированные снимки исключены.").font(.caption)
                }
                Section("Помощь") {
                    Link("Поддержка и инструкции", destination: URL(string: "https://cleaner.yeti3.ru/static/cleaner/apple/app-support.html")!)
                    Link("Написать разработчику", destination: URL(string: "mailto:ursolov@gmail.com?subject=YETI3%20Cleaner%20iOS")!)
                    Text("В письме укажите версию приложения, устройство и действия до ошибки. Не прикладывайте личные фото и контакты без необходимости.").font(.caption)
                }
                Section("Данные приложения") {
                    Button("Сбросить временный просмотр…") { cacheConfirmation = true }
                    Button("Восстановить настройки этой стратегии") { settings.reset() }
                    NavigationLink("Конфиденциальность") { PrivacyView() }
                    Text("Версия 1.0.0 (2) · iOS 17+").font(.caption)
                }
            }.disabled(model.busy).navigationTitle("Настройки")
            .confirmationDialog("Сбросить только временные данные Cleaner?", isPresented: $cacheConfirmation, titleVisibility: .visible) { Button("Сбросить", role: .destructive) { model.clearCache() }; Button("Отмена", role: .cancel) {} }
        }
    }
    private func option<T>(_ key: WritableKeyPath<ScanOptions, T>) -> Binding<T> {
        Binding(get: { settings.options[keyPath: key] }, set: { value in var options = settings.options; options[keyPath: key] = value; settings.options = options })
    }
}
struct PrivacyView: View {
    var body: some View {
        List {
            Text("Обработка на устройстве").font(.title.bold())
            Text("Фото, видео, файлы и контакты анализируются локально. Приложение не содержит рекламы, аналитики, аккаунтов или серверной загрузки пользовательских данных.")
            Text("Доступ к Фото и Контактам запрашивается только при включении соответствующего анализа. Можно предоставить ограниченный доступ и отозвать его в Настройках iOS.")
            Text("Выбранные файлы доступны через системный выбор документов. Облачный провайдер может использовать сеть самостоятельно. Cleaner не запрашивает загрузку оригиналов из iCloud Фото.")
            Text("Результаты анализа и разрешённые пути хранятся только в памяти текущей сессии. Настройки стратегий сохраняются на устройстве. Удаление приложения удаляет его собственные данные.")
            Text("Удаление фото и файлов требует отдельного подтверждения. Оно может синхронизироваться через iCloud или другого провайдера. Избранные фото защищены. Контакты редактируются только через системный интерфейс.")
            Text("Оптимизация создаёт JPEG-копию с потерей части качества и метаданных, сохраняя оригинал. Сохранение копии само по себе не освобождает место.")
        }.navigationTitle("Конфиденциальность")
    }
}

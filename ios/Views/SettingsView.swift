import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var model: CleanerModel
    @State private var cacheConfirmation = false
    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 22) {
                CleanerSection {
                    Label("YETI³ · Ваши правила", systemImage: "slider.horizontal.3").font(.title2.bold()).foregroundStyle(.cyan)
                    Text("Три независимых профиля. Категории, защита и скорость анализа настраиваются отдельно. Личные данные удаляются только после вашего подтверждения.").font(.subheadline).foregroundStyle(.secondary)
                }

                CleanerSection("Стратегия очистки") {
                    CleanerMenu("Режим", selection: $settings.strategy, identifier: "strategyPicker") { ForEach(Strategy.allCases) { Text(YetiL10n.text($0.title)).tag($0) } }
                    Text(YetiL10n.text(settings.strategy.detail)).font(.footnote)
                    Text("Настройки сохраняются отдельно для каждой стратегии. Личные данные удаляются только после dry run и подтверждения.").font(.caption)
                }
                CleanerSection("Автоматический dry run") {
                    Toggle("Анализировать при открытии приложения", isOn: $settings.automation.enabled)
                    CleanerMenu("Не чаще", selection: $settings.automation.intervalHours) {
                        Text("Каждые 6 часов").tag(6); Text("Раз в день").tag(24); Text("Раз в неделю").tag(168)
                    }
                    Toggle("Только на зарядке", isOn: $settings.automation.requireCharging)
                    Stepper("Заряд не ниже \(settings.automation.minimumBatteryPercent)%", value: $settings.automation.minimumBatteryPercent, in: 20...90, step: 10)
                    Text("Без запросов новых разрешений и удаления. При энергосбережении и перегреве анализ откладывается. iOS не гарантирует запуск по расписанию в закрытом приложении. Фото и файлы выбираете вы; контакты изменяются только вручную.").font(.caption)
                }
                CleanerSection("Защита личных данных") {
                    Label("Избранное и последняя копия защищены всегда", systemImage: "lock.shield.fill").foregroundStyle(.cyan)
                    Stepper("Защищать свежие фото: \(settings.options.recentProtectionDays) дн.", value: option(\.recentProtectionDays), in: 0...365)
                    Toggle("Защищать серии снимков", isOn: option(\.protectBursts))
                    Text("Свежие фото нельзя выбрать для удаления. 0 отключает только защиту по дате. Фото без даты защищены при включённом пороге.").font(.caption)
                }
                CleanerSection("Локальное сканирование") {
                    Toggle("Медиатека", isOn: option(\.photos))
                    Toggle("Включать видео в анализ", isOn: option(\.includeVideos)).disabled(!settings.options.photos)
                    Toggle("Похожие фото", isOn: option(\.similar)).disabled(!settings.options.photos)
                    Toggle("Старые скриншоты", isOn: option(\.screenshots)).disabled(!settings.options.photos)
                    Toggle("Выбранные файлы", isOn: option(\.files))
                    Toggle("Контакты", isOn: option(\.contacts))
                    Stepper("Скриншоты старше \(settings.options.screenshotDays) дней", value: option(\.screenshotDays), in: 7...730, step: 7)
                    Stepper("Крупные объекты от \(settings.options.largeMegabytes) МБ", value: option(\.largeMegabytes), in: 10...2000, step: 10)
                }
                CleanerSection("Период медиатеки") {
                    CleanerMenu("Дата съёмки", selection: option(\.photoLookbackDays)) {
                        Text("За всё время").tag(0); Text("Последние 30 дней").tag(30); Text("Последние 90 дней").tag(90); Text("Последний год").tag(365)
                    }
                    Text("Объекты вне периода пропускаются. Без даты — только в режиме «За всё время». Лимит размера медиатеки остаётся защитой от долгого перебора.").font(.caption)
                }
                CleanerSection("Видео и похожие фотографии") {
                    Stepper("Крупное видео от \(settings.options.largeVideoMegabytes) МБ", value: option(\.largeVideoMegabytes), in: 50...5000, step: 50)
                    Stepper("Длительность видео от \(settings.options.minimumVideoSeconds) сек", value: option(\.minimumVideoSeconds), in: 0...600, step: 15)
                    CleanerMenu("Сходство", selection: option(\.similarityDistance)) {
                        Text("Строгое").tag(3); Text("Обычное").tag(6); Text("Широкое").tag(10)
                    }
                    CleanerMenu("Интервал съёмки", selection: option(\.similarityWindowSeconds)) {
                        Text("30 секунд").tag(30); Text("2 минуты").tag(120); Text("10 минут").tag(600)
                    }
                    Text("Широкий поиск даёт больше ложных совпадений. Сравниваются до 100 соседних снимков; решение всегда за вами.").font(.caption)
                }
                CleanerSection("Правила для файлов") {
                    Stepper("Пропускать файлы меньше \(settings.options.minimumFileKilobytes) КБ", value: option(\.minimumFileKilobytes), in: 0...10240, step: 100)
                    Toggle("Анализировать только архивы", isOn: option(\.archivesOnly))
                    TextField("Исключённые расширения через запятую", text: option(\.excludedExtensions)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Только расширения (пусто — все)", text: option(\.includedExtensions)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Исключённые имена папок через запятую", text: option(\.excludedFolderNames)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    CleanerMenu("Размер одного файла до", selection: option(\.maximumFileMegabytes)) {
                        Text("Без ограничения").tag(0); Text("100 МБ").tag(100); Text("1 ГБ").tag(1024); Text("10 ГБ").tag(10240)
                    }
                    CleanerMenu("Изменён не позднее", selection: option(\.minimumFileAgeDays)) {
                        Text("Любая дата").tag(0); Text("7 дней назад").tag(7); Text("30 дней назад").tag(30); Text("90 дней назад").tag(90)
                    }
                    CleanerMenu("Глубина папок", selection: option(\.directoryDepth)) {
                        Text("Все вложенные").tag(0); Text("Только выбранная папка").tag(1); Text("До 3 уровней").tag(3); Text("До 5 уровней").tag(5)
                    }
                    Text("По умолчанию исключены ключи и сертификаты. Скрытые файлы, ссылки и содержимое пакетов пропускаются. Правила действуют при следующем анализе.").font(.caption)
                }
                CleanerSection("Правила для контактов") {
                    Toggle("Совпадение телефонов", isOn: option(\.matchContactPhones))
                    Toggle("Совпадение email", isOn: option(\.matchContactEmails))
                    Toggle("Показывать неполные записи", isOn: option(\.showIncompleteContacts))
                    Stepper("Не менее \(settings.options.minimumPhoneDigits) цифр в телефоне", value: option(\.minimumPhoneDigits), in: 7...15)
                    Text("Код страны не угадывается. Совпадения требуют ручной проверки; автоматического слияния нет.").font(.caption)
                }
                CleanerSection("Производительность") {
                    Toggle("Экономный анализ", isOn: option(\.economical))
                    Toggle("Допускать небольшой нагрев", isOn: option(\.allowFairThermalState))
                    CleanerMenu("Пауза экономного режима", selection: option(\.economicalPauseMilliseconds)) {
                        Text("20 мс").tag(20); Text("50 мс").tag(50); Text("100 мс").tag(100)
                    }
                    CleanerMenu("Лимит времени на категорию", selection: option(\.analysisSeconds)) {
                        Text("30 секунд").tag(30); Text("2 минуты").tag(120); Text("5 минут").tag(300); Text("10 минут").tag(600)
                    }
                    CleanerMenu("Лимит медиатеки", selection: option(\.photoLimit)) {
                        Text("500 объектов").tag(500); Text("2 000 объектов").tag(2000); Text("10 000 объектов").tag(10000); Text("50 000 объектов").tag(50000)
                    }
                    CleanerMenu("Лимит файлов", selection: option(\.fileLimit)) {
                        Text("500 файлов").tag(500); Text("3 000 файлов").tag(3000); Text("10 000 файлов").tag(10000)
                    }
                    Text("Экономный режим делает короткие паузы и откладывает анализ при энергосбережении. Нагрев останавливает любой анализ. Достижение лимита не считается полным результатом.").font(.caption)
                }
                CleanerSection("Копия фотографии") {
                    Stepper("Минимальная разница размера: \(settings.options.minimumOptimizationPercent)%", value: option(\.minimumOptimizationPercent), in: 10...80, step: 5)
                    Slider(value: option(\.jpegQuality), in: 0.6...0.95, step: 0.05) { Text("Качество JPEG") }
                    Text("Качество JPEG: \(Int(settings.options.jpegQuality * 100))%")
                    CleanerMenu("Длинная сторона", selection: option(\.maxPixel)) { Text("2048 px").tag(2048); Text("2560 px").tag(2560); Text("4096 px").tag(4096) }
                    Text("Оригинал сохраняется. Копия не содержит геопозиции и EXIF. RAW, HDR, Live Photo, пространственные фото, панорамы и отредактированные снимки исключены.").font(.caption)
                }
                #if !targetEnvironment(macCatalyst)
                if #available(iOS 26, *) {
                    CleanerSection("Продолжение вашего анализа") {
                        Toggle("Продолжать начатый анализ в фоне", isOn: option(\.continueInBackground)).accessibilityIdentifier("continuedAnalysis")
                        Text("Только после нажатия «Анализировать». iOS показывает прогресс и отмену. Если система не разрешила запуск, анализ доступен на открытом экране. Лимиты времени, нагрева и экономии действуют. Ничего не удаляется в фоне.").font(.caption)
                    }
                }
                #endif
                CleanerSection("Фоновый обзор") {
                    Toggle("Разрешить короткий обзор в фоне", isOn: $settings.backgroundAnalysis).accessibilityIdentifier("backgroundAnalysis")
                    Text("Только метаданные до 250 последних объектов, максимум 10 секунд. Без хеширования, сети и удаления. Действуют настройки частоты, заряда и питания выше; энергосбережение и нагрев откладывают запуск. Время выбирает iOS.").font(.caption)
                    if let date = UserDefaults.standard.object(forKey: "backgroundSummaryDate") as? Date {
                        Text("Последний обзор: \(date.formatted())").font(.caption)
                        Text("Проверено: \(UserDefaults.standard.integer(forKey: "backgroundSummaryCount")), скриншотов: \(UserDefaults.standard.integer(forKey: "backgroundScreenshots"))").font(.caption)
                    }
                }
                CleanerSection("Реклама и доступ") {
                    NavigationLink("Сеть YETI³ без рекламы") { NetworkPurchaseView() }
                    Text("Очистка бесплатна. Контекстная реклама включена по умолчанию. Администратор может выдать доступ аккаунту или зарегистрированному устройству. Покупки подтверждает App Store.").font(.caption)
                }
                CleanerSection("Помощь") {
                    Link("Поддержка и инструкции", destination: URL(string: "https://cleaner.yeti3.ru/static/cleaner/apple/app-support.html")!)
                    Link("Написать разработчику", destination: URL(string: "mailto:ursolov@gmail.com?subject=YETI3%20Cleaner%20iOS")!)
                    Text("В письме укажите версию приложения, устройство и действия до ошибки. Не прикладывайте личные фото и контакты без необходимости.").font(.caption)
                }
                CleanerSection("Данные приложения") {
                    Button("Сбросить временный просмотр…") { cacheConfirmation = true }
                    Button("Восстановить настройки этой стратегии") { settings.reset() }
                    NavigationLink("Конфиденциальность") { PrivacyView() }
                    Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")) · iOS 17+").font(.caption)
                }
              }.padding(24).frame(maxWidth: 880)
            }.cleanerScreen().disabled(model.busy).navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
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
            Text("Фото, видео, файлы и контакты анализируются локально и не отправляются на сервер. Контекстная реклама сервисов YETI³ не анализирует личные данные. Для отключения рекламы можно войти в аккаунт сети: сервер получает email, идентификатор аккаунта и подписанную транзакцию Apple при покупке. Сессия хранится в Keychain. Отслеживания между приложениями нет.")
            Text("Доступ к Фото и Контактам запрашивается только при включении соответствующего анализа. Можно предоставить ограниченный доступ и отозвать его в Настройках iOS.")
            Text("Выбранные файлы доступны через системный выбор документов. Облачный провайдер может использовать сеть самостоятельно. Cleaner не запрашивает загрузку оригиналов из iCloud Фото.")
            Text("Результаты анализа и разрешённые пути хранятся только в памяти текущей сессии. Настройки стратегий и числовая сводка фонового обзора сохраняются на устройстве. Удаление приложения удаляет его собственные данные.")
            Text("Удаление фото и файлов требует отдельного подтверждения. Оно может синхронизироваться через iCloud или другого провайдера. Избранные фото защищены. Контакты редактируются только через системный интерфейс.")
            Text("Оптимизация создаёт JPEG-копию с потерей части качества и метаданных, сохраняя оригинал. Сохранение копии само по себе не освобождает место.")
        }.cleanerScreen().navigationTitle("Конфиденциальность")
    }
}

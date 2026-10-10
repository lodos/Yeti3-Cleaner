# Cleaner iOS · отправка

Продукт: YETI³ Cleaner · 1.0.0 (2) · ru.yeti3.cleaner.ios · ViShu 49PHJ38L7T.

1. Завершить вход владельца ViShu с двухфакторной проверкой. Зарегистрировать explicit App ID ru.yeti3.cleaner.ios без дополнительных capabilities.
2. Создать карточку App Store Connect: iOS, название YETI³ Cleaner, русский, SKU YETI3-CLEANER-IOS. Не использовать Bundle ID Node, Connector или расширения VPN.
3. Открыть ios/Yeti3Cleaner.xcodeproj, схема Yeti3Cleaner. Product → Archive → Distribute App → App Store Connect. UploadOptions.plist подготовлен для CLI-загрузки подписанного архива; актуальный архив в /tmp нельзя считать постоянным хранилищем исходников.
4. Перенести AppStoreMetadata.json в карточку, загрузить StoreAssets/screenshots/iphone-6.7 и ipad-12.9. Иконка поступает из AppIcon в сборке. Поддержка и конфиденциальность опубликованы, их URL указаны в метаданных.
5. Указать действующего контактного человека Apple Review и телефон; авторизация в приложении не нужна. Пройти анкету возраста, конфиденциальность Data Not Collected, права на контент и выбор стран/цены, сверив фактический код. Не подтверждать юридические заявления за владельца без его подтверждения.
6. Выбрать обработанную сборку 2 и отправить на проверку. Для TestFlight отдельно заполнить beta description и сценарии тестирования, добавить нужную группу.

Проверено: подписанный архив, privacy manifest, назначения разрешений, 13 файлов иконок/снимков с SHA-256, 16 тестов безопасности, интерфейс iPhone/iPad. На реальном устройстве в этом запуске не проверены PhotoKit limited access, iCloud и File Provider; см. VERIFICATION.md. Успешная подготовка не означает успешную загрузку или одобрение Apple.

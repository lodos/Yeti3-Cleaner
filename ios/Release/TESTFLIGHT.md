# Подготовка к TestFlight

Подготовлен iOS-проект с automatic signing для ViShu (`49PHJ38L7T`). Подписанный архив 1.0.0 (2) собран 10.10.2026. Регистрация `ru.yeti3.cleaner.ios` и создание карточки App Store Connect пока заблокированы: текущая сессия Developer Portal показывает Access Unavailable. Это не успешная загрузка или отправка на проверку.

## Параметры

- Deployment target: iOS 17.0; iPhone и iPad; без Mac Catalyst.
- Version/build: 1.0.0 / 2. Перед повторной загрузкой увеличивать build.
- Signing: Automatic; в Xcode → Settings → Accounts войти в нужный Apple ID, пройти 2FA, выбрать платную команду Developer Program в Signing & Capabilities.
- Bundle ID должен совпадать с зарегистрированным App ID и карточкой App Store Connect. При изменении обновить `project.yml` и сгенерировать проект.
- Специальные capabilities не нужны. Пустой entitlements-файл намеренный. Доступы к Photo Library и Contacts задаются usage descriptions, Files — системным picker. iCloud entitlement для чтения PhotoKit или выбранного документа не требуется. Нет Push, Background Modes, App Groups, Tracking, Contacts Notes.
- Export compliance: стандартные системные API, без собственной криптографии передачи данных. SHA-256 используется локально для проверки совпадений. `ITSAppUsesNonExemptEncryption = NO`; перепроверить при добавлении сетевых функций.

## Последовательность выпуска

1. Подтвердить Team ID и свободный Bundle ID; принять договоры Apple. Создать карточку iOS-приложения в App Store Connect с тем же идентификатором и уникальным SKU.
2. Указать юридического владельца, рабочие Support URL и Privacy Policy URL, copyright, email/телефон контактного лица App Review. Неподтверждённые поля метаданных оставлены пустыми и блокируют выпуск.
3. Опубликовать `privacy-policy.html`, заполнив владельца и контакт; публичную политику сверить с окончательной версией приложения.
4. Пройти матрицу ручных тестов в VERIFICATION.md на отдельном наборе тестовых данных реального iPhone. Особенно limited access, iCloud и File Provider. Снимки экрана снять с окончательной версии iPhone и iPad.
5. В Xcode выбрать Any iOS Device → Product → Archive. Либо запустить `TEAM_ID=XXXXXXXXXX ./scripts/archive.sh`. Скрипт создаёт локальный подписанный архив, ничего не загружает.
6. Organizer → Validate App → Distribute App → App Store Connect. Разрешить автоматическое управление подписью. При необходимости Xcode создаст distribution certificate/profile в выбранной команде.
7. Дождаться processing в App Store Connect, заполнить TestFlight beta description, What to Test и контактную информацию. Добавить внутренних тестировщиков. Для внешнего тестирования пройти Beta App Review.
8. Не путать успешную компиляцию, подписанный архив, успешную загрузку, processing и доступность TestFlight: это отдельные этапы.

## Privacy labels

Для текущего кода: Data Not Collected. Фото/видео, контакты, файлы обрабатываются исключительно на устройстве, не поступают разработчику. Нет Tracking, рекламы, SDK аналитики и связывания данных с аккаунтом. Ограничения PhotoKit и File Provider отражены в пользовательской политике. Перепроверить ответы при добавлении SDK, crash reporting, поддержки с вложениями или сети.

Privacy manifest: `CA92.1` — собственные настройки; `85F4.1` — отображение дискового пространства; `3B52.1` — метаданные файлов, к которым пользователь предоставил доступ. Тексты причин сверены с документацией Apple 08.10.2026.

## Источники Apple

- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
- https://developer.apple.com/documentation/contacts/accessing-the-contact-store

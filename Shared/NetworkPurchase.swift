// Shared YETI3 network monetization SDK.
import Foundation
import StoreKit
import SwiftUI
import Security

@MainActor public final class NetworkPurchase: ObservableObject {
    public static let shared = NetworkPurchase()
    public static let months = [1, 2, 3, 6, 12, 24, 36]
    public static let productIDs = months.map { "ru.yeti3.network.ads.\($0)m" }
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var adsEnabled = true
    @Published public private(set) var busy = false
    @Published public private(set) var checkoutReady = false
    @Published public private(set) var message = ""
    @Published public private(set) var accountID: UUID?
    private var token: String?
    private var updates: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private var starting = false
    @Published public private(set) var deviceID: String?
    private var sessionGeneration = UUID()
    private var sandbox = false
    private var confirmedExpiry: Date?
    private let base = URL(string: "https://license.gochain.space")!
    private let service = "ru.yeti3.network.purchase.session"
    private init() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "licensing", kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let d = result as? Data { token = String(data: d, encoding: .utf8) }
    }
    public func start() async {
        guard !starting else { return }; starting = true; defer { starting = false }
        if updates == nil {
            updates = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    guard let self else { return }
                    do { try await self.deliver(result) } catch { self.message = "Покупка ожидает подтверждения сервера. Повторите восстановление." }
                }
            }
        }
        await refresh()
        // StoreKit products are fetched only when the purchase screen opens.
    }
    public func signOut() {
        expiryTask?.cancel(); expiryTask = nil
        sessionGeneration = UUID()
        token = nil; accountID = nil; deviceID = nil; adsEnabled = true
        confirmedExpiry = nil; lastRefresh = nil; sandbox = false
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "licensing"]
        SecItemDelete(query as CFDictionary)
        // ThisDeviceOnly device bindings survive sign-out, scoped to their network account.
        message = "Вы вышли из аккаунта. Очистка остаётся доступной."
    }
    public func registerDevice() async {
        guard !busy, let accountID else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await call("api/network/v1/compute/devices", method: "POST", body: ["name": "YETI3 Cleaner", "native": false])
            guard let id = result["id"] as? String, id.count == 32, id.allSatisfy({ $0.isHexDigit }) else { throw URLError(.cannotParseResponse) }
            // No compute worker, heartbeat or workload is started. The credential is discarded.
            deviceID = id
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device-" + accountID.uuidString]
            let attributes: [String: Any] = [kSecValueData as String: Data(id.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updated == errSecItemNotFound {
                var insert = query; attributes.forEach { insert[$0] = $1 }
                guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
            } else if updated != errSecSuccess { throw URLError(.cannotWriteToFile) }
            lastRefresh = nil; await refresh()
            message = "Устройство зарегистрировано для административного доступа."
        } catch { message = "Регистрация устройства недоступна. Доступ аккаунта продолжает работать." }
    }

    private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "/" + path, relativeTo: base)!.absoluteURL); request.httpMethod = method; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        return value
    }
    public func signIn(email: String, password: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        signOut()
        do {
            let response = try await call("api/network/v1/auth/login", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
            guard let t = response["token"] as? String else { throw URLError(.userAuthenticationRequired) }
            token = t
            await refresh()
            guard accountID != nil else { throw URLError(.userAuthenticationRequired) }
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "licensing"]
            let attributes: [String: Any] = [kSecValueData as String: Data(t.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let updated = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
            if updated == errSecItemNotFound { var insert = q; attributes.forEach { insert[$0] = $1 }; guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) } }
            else if updated != errSecSuccess { throw URLError(.cannotWriteToFile) }
            message = "Аккаунт сети подключён."
        } catch { token = nil; accountID = nil; message = "Вход не выполнен. Проверьте данные и соединение." }
    }
    public func loadProducts() async {
        do {
            let availability = try await call("api/network/v1/ads/catalog")
            checkoutReady = availability["apple_checkout_ready"] as? Bool ?? false
            products = try await Product.products(for: Self.productIDs).sorted { months($0.id) < months($1.id) }; if products.isEmpty { message = "Покупки пока недоступны в App Store. Попробуйте позже." } }
        catch { checkoutReady = false; message = "Не удалось загрузить цены App Store. Проверьте соединение." }
    }
    private func months(_ id: String) -> Int { Int(id.split(separator: ".").last?.dropLast() ?? "") ?? 0 }
    private func applyAccess(_ result: [String: Any]) {
        adsEnabled = !AdAccessPolicy.allows(result)
        confirmedExpiry = (result["expires_at"] as? String).flatMap(AdAccessPolicy.expiry)
        expiryTask?.cancel()
        if !adsEnabled, let expiry = confirmedExpiry {
            let seconds = max(0, expiry.timeIntervalSinceNow)
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                self?.adsEnabled = true
            }
        }
    }

    public func refresh() async {
        if let confirmedExpiry, confirmedExpiry <= Date() { adsEnabled = true }
        guard token != nil, lastRefresh.map({ Date().timeIntervalSince($0) >= 300 }) ?? true else { return }
        lastRefresh = Date()
        let generation = sessionGeneration
        do {
            let device = deviceID.map { "&device_id=" + $0 } ?? ""
            let result = try await call("api/network/v1/ads/status?environment=\(sandbox ? "Sandbox" : "Production")\(device)")
            guard generation == sessionGeneration else { return }
            guard let raw = result["account_id"] as? String, raw.count == 32 else { throw URLError(.cannotParseResponse) }
            let chars = Array(raw); let parts = [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])]
            guard let id = UUID(uuidString: parts.joined(separator: "-")) else { throw URLError(.cannotParseResponse) }
            accountID = id; applyAccess(result)
            if deviceID == nil {
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device-" + id.uuidString, kSecReturnData as String: true]
                var saved: CFTypeRef?
                if SecItemCopyMatching(query as CFDictionary, &saved) == errSecSuccess, let data = saved as? Data,
                   let device = String(data: data, encoding: .utf8), device.count == 32, device.allSatisfy({ $0.isHexDigit }) {
                    deviceID = device; lastRefresh = nil; await refresh()
                }
            }
        } catch {
            guard generation == sessionGeneration else { return }
            // An outage does not turn an already confirmed paid session back into ads.
            message = "Статус доступа временно недоступен. Повторите при следующем открытии."
        }
    }
    public func purchase(_ product: Product) async {
        guard !busy, checkoutReady, let accountID else { message = checkoutReady ? "Сначала войдите в аккаунт сети." : "Покупки временно недоступны. Попробуйте позже."; return }
        busy = true; defer { busy = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(accountID)]) {
            case .success(let result): try await deliver(result)
            case .pending: message = "Покупка ожидает подтверждения Apple."
            case .userCancelled: message = "Покупка отменена."
            @unknown default: message = "Apple пока не подтвердила покупку."
            }
        } catch { message = "Покупка не подтверждена сервером. Нажмите «Восстановить покупки»." }
    }
    private func deliver(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { throw URLError(.cannotParseResponse) }
        guard token != nil, let accountID, transaction.appAccountToken == accountID else { throw URLError(.userAuthenticationRequired) }
        let generation = sessionGeneration
        let response = try await call("api/network/v1/ads/apple/receipt", method: "POST", body: ["signed_transaction": result.jwsRepresentation])
        guard generation == sessionGeneration else { throw URLError(.userAuthenticationRequired) }
        sandbox = response["environment"] as? String == "Sandbox"
        applyAccess(response)
        lastRefresh = nil
        await transaction.finish() // Finish only after durable server acknowledgement.
        message = adsEnabled ? "Покупка проверена. Срок доступа истёк или выполнен возврат." : "Реклама отключена для аккаунта сети."
    }
    public func restore() async {
        guard !busy, accountID != nil else { message = "Сначала войдите в аккаунт сети."; return }
        busy = true; defer { busy = false }
        do {
            try await AppStore.sync()
            var count = 0
            // Non-renewing subscriptions require transaction history, not just currentEntitlements.
            for await result in StoreKit.Transaction.all {
                if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.appAccountToken == accountID {
                    try await deliver(result); count += 1
                }
            }
            await refresh()
            if count == 0 { message = "Покупок этого аккаунта Apple не найдено." }
        } catch { message = "Восстановление не завершено. Проверьте аккаунт сети и соединение." }
    }
}

public struct NetworkPurchaseView: View {
    @ObservedObject private var store = NetworkPurchase.shared
    @State private var email = ""
    @State private var password = ""
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Сеть без рекламы").font(.largeTitle.bold())
                Text("Один доступ для всех продуктов YETI³ на вашем аккаунте. Выберите срок; продление вручную.").foregroundStyle(.secondary)
                if store.accountID == nil {
                    TextField("Email аккаунта сети", text: $email).textContentType(.username)
                    SecureField("Пароль", text: $password).textContentType(.password)
                    Button("Войти") { let secret = password; password = ""; Task { await store.signIn(email: email, password: secret) } }.disabled(store.busy || email.isEmpty || password.isEmpty)
                }
                if store.accountID != nil {
                    if let id = store.deviceID { Text("Устройство: " + id).font(.caption.monospaced()).textSelection(.enabled) }
                    else { Button("Зарегистрировать это устройство") { Task { await store.registerDevice() } }.disabled(store.busy) }
                    Text("Регистрация нужна только для исключения рекламы администратором на этом устройстве. Вычисления в фоне не включаются.").font(.caption).foregroundStyle(.secondary)
                    Button("Выйти из аккаунта") { store.signOut() }.disabled(store.busy)
                }
                if !store.adsEnabled { Label("Реклама отключена", systemImage: "checkmark.seal.fill").foregroundStyle(.cyan) }
                ForEach(store.products) { product in
                    HStack {
                        VStack(alignment: .leading) { Text(product.displayName).font(.headline); Text(product.description).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button(product.displayPrice) { Task { await store.purchase(product) } }.buttonStyle(.borderedProminent).disabled(store.busy || !store.checkoutReady || store.accountID == nil)
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                if !store.checkoutReady { Text("Покупки временно недоступны. Восстановление остаётся доступным.").font(.callout).foregroundStyle(.secondary) }
                if store.busy { ProgressView("Подтверждаем…") }
                Text(YetiL10n.text(store.message)).font(.callout).accessibilityIdentifier("network.purchase.status")
                Button("Восстановить покупки") { Task { await store.restore() } }.disabled(store.busy || store.accountID == nil)
                Button("Обновить цены") { Task { await store.loadProducts() } }.disabled(store.busy)
                HStack { Link("Условия", destination: URL(string: "https://license.gochain.space/legal/terms")!); Link("Конфиденциальность", destination: URL(string: "https://license.gochain.space/legal/privacy")!) }.font(.caption)
            }.padding(24)
        }.frame(minWidth: 300).tint(.cyan).task { await store.start(); await store.loadProducts() }
    }
}

/// Contextual network promotion; never reads files, VPN traffic or device identifiers.
public struct NetworkAdBanner: View {
    @ObservedObject private var store = NetworkPurchase.shared
    @State private var showPurchase = false
    public init() {}
    public var body: some View {
        if store.adsEnabled {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("РЕКЛАМА · YETI³").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text("LineCloud · рендер Blender в облаке").font(.callout.weight(.medium))
                }
                HStack {
                Link("Подробнее", destination: URL(string: "https://linecloud.ru/")!).font(.caption)
                Button("Без рекламы") { showPurchase = true }.font(.caption).buttonStyle(.bordered)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                .sheet(isPresented: $showPurchase) { VStack { HStack { Spacer(); Button("Готово") { showPurchase = false } }.padding(); NetworkPurchaseView() }.frame(idealWidth: 560, idealHeight: 680) }
                .task { await store.start() }
        }
    }
}

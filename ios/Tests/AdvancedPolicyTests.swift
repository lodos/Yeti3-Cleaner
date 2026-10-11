import XCTest
@testable import Yeti3Cleaner

final class AdvancedPolicyTests: XCTestCase {
    func testOldProfilePreservesChoicesAndAddsSafeDefaults() throws {
        let old = Data(#"{"photos":false,"jpegQuality":0.7,"screenshotDays":180}"#.utf8)
        let options = try JSONDecoder().decode(ScanOptions.self, from: old)
        XCTAssertFalse(options.photos)
        XCTAssertEqual(options.jpegQuality, 0.7)
        XCTAssertEqual(options.screenshotDays, 180)
        XCTAssertEqual(options.recentProtectionDays, 7)
        XCTAssertTrue(options.economical)
        XCTAssertEqual(try JSONDecoder().decode(ScanOptions.self, from: JSONEncoder().encode(options)), options)
    }
    func testFreshAndUndatedPhotosAreProtected() {
        var options = ScanOptions(); let now = Date()
        XCTAssertTrue(options.protects(date: now, now: now))
        XCTAssertTrue(options.protects(date: nil, now: now))
        XCTAssertFalse(options.protects(date: now.addingTimeInterval(-8 * 86400), now: now))
        options.recentProtectionDays = 0
        XCTAssertFalse(options.protects(date: nil, now: now))
    }
    func testFileRulesExcludeSecretsAndApplySizeAndArchiveSelection() {
        var options = ScanOptions()
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/secret.PEM"), bytes: 200_000))
        options.minimumFileKilobytes = 100
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/a.txt"), bytes: 100))
        XCTAssertTrue(options.includesFile(URL(fileURLWithPath: "/fixture/a.txt"), bytes: 200_000))
        options.archivesOnly = true
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/a.txt"), bytes: 200_000))
        XCTAssertTrue(options.includesFile(URL(fileURLWithPath: "/fixture/a.zip"), bytes: 200_000))
    }
    func testFileAllowlistCannotBypassSecretExclusionOrSizeBound() {
        var options = ScanOptions(); options.includedExtensions = "txt, .PEM"; options.maximumFileMegabytes = 1
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/a.pem"), bytes: 10))
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/a.jpg"), bytes: 10))
        XCTAssertFalse(options.includesFile(URL(fileURLWithPath: "/fixture/a.txt"), bytes: 1_048_577))
        XCTAssertTrue(options.includesFile(URL(fileURLWithPath: "/fixture/a.TXT"), bytes: 1_048_576))
    }
    func testUnknownDatesFailClosedWhenAgeFiltersAreEnabled() {
        var options = ScanOptions(); let now = Date()
        options.photoLookbackDays = 30; options.minimumFileAgeDays = 7
        XCTAssertFalse(options.includesPhoto(date: nil, now: now))
        XCTAssertFalse(options.includesFileDate(nil, now: now))
        XCTAssertTrue(options.includesPhoto(date: now.addingTimeInterval(-86400), now: now))
        XCTAssertFalse(options.includesFileDate(now, now: now))
        XCTAssertTrue(options.includesFileDate(now.addingTimeInterval(-8 * 86400), now: now))
    }
    func testRecursiveFileRulesSkipExcludedTreesAndRespectDepth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["node_modules/deep", "notes/deep"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: root.appendingPathComponent(folder + "/a.txt"))
        }
        try Data("root".utf8).write(to: root.appendingPathComponent("root.txt"))
        let service = FileService()
        let normal = try await service.scan(roots: [root], progress: { _ in })
        XCTAssertEqual(normal.items.count, 2)
        XCTAssertFalse(normal.items.contains { $0.url.path.contains("node_modules") })
        var shallow = ScanOptions(); shallow.directoryDepth = 1
        let limited = try await service.scan(roots: [root], options: shallow, progress: { _ in })
        XCTAssertEqual(limited.items.map(\.url.lastPathComponent), ["root.txt"])
    }
    #if !targetEnvironment(macCatalyst)
    @MainActor func testContinuedAnalysisCanCompleteAndBeSubmittedAgain() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Requires iOS 26") }
        for _ in 0..<2 {
            let accepted = await ContinuedAnalysis.shared.begin(cancel: {})
            print("Continued analysis accepted by device: \(accepted)")
            if accepted {
                let overlapping = await ContinuedAnalysis.shared.begin(cancel: {})
                XCTAssertFalse(overlapping)
            }
            ContinuedAnalysis.shared.update(0.5, subtitle: "Проверка запуска без чтения личных данных")
            ContinuedAnalysis.shared.finish(success: true)
        }
    }
    @MainActor func testStartedFileAnalysisSurvivesBackgroundTransition() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Requires iOS 26") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<100 { try Data("fixture-\(index)".utf8).write(to: root.appendingPathComponent("\(index).txt")) }
        var options = ScanOptions(); options.photos = false; options.continueInBackground = true
        let model = CleanerModel(); model.roots = [root]; model.scan(options)
        let deadline = Date().addingTimeInterval(15)
        while !ContinuedAnalysis.shared.isActive && model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard ContinuedAnalysis.shared.isActive else { model.cancel(); throw XCTSkip("System did not accept continued job on this run") }
        model.backgrounded()
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.busy); XCTAssertNotNil(model.lastScan); XCTAssertEqual(model.files.items.count, 100)
        model.cancel()
    }
    #endif

    func testAdAccessRejectsExpiredMalformedAndUnconfirmedGrants() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AdAccessPolicy.allows([:], now: now))
        XCTAssertFalse(AdAccessPolicy.allows(["ads_enabled": false, "source": "APPLE"], now: now))
        XCTAssertFalse(AdAccessPolicy.allows(["ads_enabled": false, "expires_at": "garbage"], now: now))
        XCTAssertFalse(AdAccessPolicy.allows(["ads_enabled": false, "expires_at": "2020-01-01T00:00:00Z"], now: now))
        XCTAssertTrue(AdAccessPolicy.allows(["ads_enabled": false, "source": "ADMIN"], now: now))
        XCTAssertTrue(AdAccessPolicy.allows(["ads_enabled": false, "expires_at": "2030-01-01T00:00:00.123456"], now: now))
        XCTAssertNotNil(AdAccessPolicy.expiry("2030-01-01T00:00:00+03:00"))
    }
    func testFileServiceActuallyAppliesExclusions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("private".utf8).write(to: root.appendingPathComponent("secret.pem"))
        try Data("normal".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let report = try await FileService().scan(roots: [root], progress: { _ in })
        XCTAssertEqual(report.items.map(\.url.lastPathComponent), ["notes.txt"])
        XCTAssertEqual(report.skipped, 1)
    }
}

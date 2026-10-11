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

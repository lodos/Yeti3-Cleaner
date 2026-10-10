import XCTest
import UIKit
import ImageIO
@testable import Yeti3Cleaner

final class SafetyTests: XCTestCase {
    func testCannotDeleteEntireDuplicateGroup() {
        XCTAssertFalse(SafetyPolicy.deletionAllowed(selected: ["a","b"], known: ["a","b","c"], duplicateGroups: [["a","b"]]))
        XCTAssertTrue(SafetyPolicy.deletionAllowed(selected: ["a"], known: ["a","b","c"], duplicateGroups: [["a","b"]]))
    }
    func testEmptyAndUnknownSelectionsFailClosed() {
        XCTAssertFalse(SafetyPolicy.deletionAllowed(selected: [], known: ["a"], duplicateGroups: []))
        XCTAssertFalse(SafetyPolicy.deletionAllowed(selected: ["x"], known: ["a"], duplicateGroups: []))
    }
    func testPathBoundaries() {
        let root = URL(fileURLWithPath: "/tmp/selected")
        XCTAssertTrue(SafetyPolicy.isInside(root.appendingPathComponent("file"), root: root))
        XCTAssertFalse(SafetyPolicy.isInside(URL(fileURLWithPath: "/tmp/selected-other/file"), root: root))
        XCTAssertFalse(SafetyPolicy.isInside(root.appendingPathComponent("../secret"), root: root))
        XCTAssertFalse(SafetyPolicy.isInside(root, root: root))
    }
    func testOptimizationMustActuallySaveTenPercent() {
        XCTAssertFalse(SafetyPolicy.optimizationSavesSpace(original: 100, output: 100))
        XCTAssertFalse(SafetyPolicy.optimizationSavesSpace(original: 100, output: 95))
        XCTAssertFalse(SafetyPolicy.optimizationSavesSpace(original: 100, output: 0))
        XCTAssertTrue(SafetyPolicy.optimizationSavesSpace(original: 100, output: 89))
    }
    func testIndependentStrategyDefaultsAndRoundTrip() throws {
        XCTAssertFalse(ScanOptions.preset(.safe).similar)
        XCTAssertFalse(ScanOptions.preset(.safe).contacts)
        XCTAssertTrue(ScanOptions.preset(.balanced).similar)
        XCTAssertTrue(ScanOptions.preset(.balanced).contacts)
        XCTAssertFalse(ScanOptions.preset(.manual).photos)
        var value = ScanOptions.preset(.balanced); value.jpegQuality = 0.7
        XCTAssertEqual(try JSONDecoder().decode(ScanOptions.self, from: JSONEncoder().encode(value)), value)
    }
    func testPhoneNormalizationDoesNotInferCountry() {
        XCTAssertEqual(SafetyPolicy.normalizedPhone("+7 (999) 123-45-67"), "79991234567")
        XCTAssertNotEqual(SafetyPolicy.normalizedPhone("89991234567"), SafetyPolicy.normalizedPhone("+79991234567"))
    }
}
final class FileServiceTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    func write(_ name: String, _ data: String) throws -> URL {
        let path = root.appendingPathComponent(name); try Data(data.utf8).write(to: path); return path
    }
    func testStreamingHashFindsDuplicatesAndSkipsSymlinks() async throws {
        let a = try write("a.txt", "same"); _ = try write("b.txt", "same"); _ = try write("c.txt", "other")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: a)
        let report = try await FileService().scan(roots: [root, root], progress: { _ in })
        XCTAssertEqual(report.items.count, 3); XCTAssertEqual(report.duplicates.count, 1)
        XCTAssertEqual(report.duplicates.first?.count, 2); XCTAssertEqual(report.skipped, 1)
    }
    func testChangedFileIsNotDeleted() async throws {
        let file = try write("a.txt", "first")
        let service = FileService(); let report = try await service.scan(roots: [root], progress: { _ in })
        try Data("changed".utf8).write(to: file)
        let errors = try await service.delete(report.items, report: report)
        XCTAssertEqual(errors.count, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testWholeDuplicateGroupCannotBeDeleted() async throws {
        _ = try write("a.txt", "same"); _ = try write("b.txt", "same")
        let service = FileService(); let report = try await service.scan(roots: [root], progress: { _ in })
        do { _ = try await service.delete(report.items, report: report); XCTFail("Expected refusal") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }
    func testConfirmedSelectionDeletesOnlyChosenFixture() async throws {
        _ = try write("a.txt", "same"); _ = try write("b.txt", "same")
        let service = FileService(); let report = try await service.scan(roots: [root], progress: { _ in })
        let errors = try await service.delete([report.items[0]], report: report)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
    func testMissingKeeperPreventsDeletionOfLastCopy() async throws {
        _ = try write("a.txt", "same"); _ = try write("b.txt", "same")
        let service = FileService(); let report = try await service.scan(roots: [root], progress: { _ in })
        try FileManager.default.removeItem(at: report.items[1].url)
        do { _ = try await service.delete([report.items[0]], report: report); XCTFail("Must retain last copy") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.items[0].url.path))
    }
    func testReplacedSymlinkIsNotDeleted() async throws {
        let path = try write("a.txt", "content"); let target = try write("b.txt", "important")
        let service = FileService(); let report = try await service.scan(roots: [root], progress: { _ in })
        let item = try XCTUnwrap(report.items.first { $0.url == path })
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        let errors = try await service.delete([item], report: report)
        XCTAssertEqual(errors.count, 1); XCTAssertEqual(try String(contentsOf: target), "important")
    }
}

final class PhotoEncoderTests: XCTestCase {
    func testDownsampleProducesReadableCopyWithoutChangingInput() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            for x in stride(from: 0, to: 3000, by: 10) {
                UIColor(hue: CGFloat(x)/3000, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: 0, width: 10, height: 2000))
            }
        }
        let original = try XCTUnwrap(source.jpegData(compressionQuality: 1))
        let originalCopy = original
        var options = ScanOptions(); options.maxPixel = 1024; options.jpegQuality = 0.7
        let encoded = try PhotoEncoder.encode(original, options: options)
        XCTAssertEqual(original, originalCopy)
        XCTAssertLessThan(encoded.count, original.count)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(image.width, 1024); XCTAssertLessThanOrEqual(image.height, 1024)
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary])
    }
    func testMalformedImageFailsWithoutCreatingOutput() {
        XCTAssertThrowsError(try PhotoEncoder.encode(Data("not an image".utf8), options: ScanOptions()))
    }
}

final class CleanupPolicyTests: XCTestCase {
    func testAutomationRequiresOptInPowerAndSafeTemperature() {
        var policy = AutomationPolicy(); let now = Date()
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: 100, charging: true, lowPower: false, thermalSafe: true))
        policy.enabled = true
        XCTAssertTrue(policy.due(now: now, lastAttempt: nil, batteryPercent: nil, charging: true, lowPower: false, thermalSafe: true))
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: 100, charging: false, lowPower: false, thermalSafe: true))
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: 100, charging: true, lowPower: true, thermalSafe: true))
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: 100, charging: true, lowPower: false, thermalSafe: false))
        XCTAssertFalse(policy.due(now: now, lastAttempt: now, batteryPercent: 100, charging: true, lowPower: false, thermalSafe: true))
        policy.requireCharging = false
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: nil, charging: false, lowPower: false, thermalSafe: true))
        XCTAssertFalse(policy.due(now: now, lastAttempt: nil, batteryPercent: 20, charging: false, lowPower: false, thermalSafe: true))
    }
    func testDryRunRejectsUnknownLastDuplicateAndMissingScan() {
        let now = Date(); let sizes: [String:Int64] = ["a": 100, "b": 100]
        XCTAssertFalse(CleanupDryRun.make(selected: ["a", "b"], sizes: sizes, groups: [["a", "b"]], scanDate: now).allowed)
        XCTAssertFalse(CleanupDryRun.make(selected: ["unknown"], sizes: sizes, groups: [], scanDate: now).allowed)
        XCTAssertFalse(CleanupDryRun.make(selected: ["a"], sizes: sizes, groups: [], scanDate: nil).allowed)
        let plan = CleanupDryRun.make(selected: ["a"], sizes: sizes, groups: [["a", "b"]], scanDate: now, now: now)
        XCTAssertEqual(plan.estimatedBytes, 100)
        XCTAssertTrue(plan.isCurrent(selection: ["a"], scanDate: now, now: now))
        XCTAssertFalse(plan.isCurrent(selection: ["b"], scanDate: now, now: now))
        XCTAssertFalse(plan.isCurrent(selection: ["a"], scanDate: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(plan.isCurrent(selection: ["a"], scanDate: now, now: now.addingTimeInterval(901)))
    }
}

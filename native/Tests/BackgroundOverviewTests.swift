import Foundation
import Darwin

@main struct BackgroundOverviewTests {
    static func main() async throws {
        setbuf(stdout, nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("local".utf8).write(to: root.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("must not be counted".utf8).write(to: root.appendingPathComponent("nested/b.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("a.txt"))
        let summary = try await NativeBackgroundOverview.overview(root, environmentSafe: { true })
        guard summary.contains("файлов: 1,"), FileManager.default.fileExists(atPath: root.appendingPathComponent("nested/b.txt").path) else { fatalError("Shallow overview or no-write guarantee failed") }
        do { _ = try await NativeBackgroundOverview.overview(root, environmentSafe: { false }); fatalError("Unsafe thermal/power condition ignored") } catch is CancellationError { }
        print("PASS: unsafe environment stops work")
        print("PASS: no traversal of nested folders or symlinks; no deletion")
        for index in 0..<300 { try Data().write(to: root.appendingPathComponent("fixture-\(index)")) }
        let capped = try await NativeBackgroundOverview.overview(root, environmentSafe: { true }, pauseMilliseconds: 0)
        let count = Int(capped.components(separatedBy: "файлов: ")[1].split(separator: ",")[0]) ?? 9999
        guard count <= 250 else { fatalError("Overview exceeded cap") }
        print("PASS: bounded overview")
        let task = Task { try await NativeBackgroundOverview.overview(root, environmentSafe: { true }) }
        try await Task.sleep(for: .milliseconds(100)); let start = Date(); task.cancel()
        do { _ = try await task.value; fatalError("Cancelled work completed") } catch is CancellationError { }
        guard Date().timeIntervalSince(start) < 1 else { fatalError("Cancellation stalled") }
        print("PASS: cooperative cancellation under one second")
    }
}

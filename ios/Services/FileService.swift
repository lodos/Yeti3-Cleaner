import Foundation
import CryptoKit

struct FileItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let root: URL
    let digest: ContentDigest
    let modified: Date?
    var duplicate = false
    var archive: Bool { ["zip", "rar", "7z", "tar", "gz", "dmg"].contains(url.pathExtension.lowercased()) }
}
struct FileReport {
    var items: [FileItem] = []
    var duplicates: [[String]] = []
    var skipped = 0
}
actor FileService {
    static func fingerprint(_ url: URL, budget: AnalysisBudget? = nil) throws -> ContentDigest {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256(); var size: Int64 = 0
        while let data = try handle.read(upToCount: 1024*1024), !data.isEmpty {
            try Task.checkCancellation(); try budget?.check(); hasher.update(data: data); size += Int64(data.count)
        }
        return .init(hash: hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes: size)
    }
    func scan(roots: [URL], options: ScanOptions = ScanOptions(), progress: @escaping @Sendable (Int) async -> Void) async throws -> FileReport {
        let budget = AnalysisBudget(options: options)
        var report = FileReport(); var seen: Set<String> = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey]
        for root in roots {
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            let values = try root.resourceValues(forKeys: keys)
            let urls: AnySequence<URL>
            if values.isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in report.skipped += 1; return true }) else { report.skipped += 1; continue }
                urls = AnySequence { AnyIterator { enumerator.nextObject() as? URL } }
            } else { urls = AnySequence([root]) }
            for url in urls {
                try await budget.yield()
                guard report.items.count < max(100, options.fileLimit) else { throw CleanerError.message("Достигнут лимит файлов. Сузьте выбранную папку или увеличьте лимит.") }
                guard seen.insert(url.path).inserted else { continue }
                do {
                    let value = try url.resourceValues(forKeys: keys)
                    if value.isDirectory == true { continue }
                    guard value.isRegularFile == true, value.isSymbolicLink != true,
                          url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path,
                          value.isUbiquitousItem != true || value.ubiquitousItemDownloadingStatus == .current else { report.skipped += 1; continue }
                    guard options.includesFile(url, bytes: Int64(value.fileSize ?? 0)) else { report.skipped += 1; continue }
                    var coordinationError: NSError?; var outcome: Result<ContentDigest, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
                        outcome = Result { try Self.fingerprint(coordinated, budget: budget) }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let outcome else { throw CleanerError.message("Файл недоступен") }
                    let digest = try outcome.get()
                    report.items.append(.init(url: url, root: root, digest: digest, modified: value.contentModificationDate))
                    await progress(report.items.count)
                } catch is CancellationError { throw CancellationError() }
                catch { try budget.check(); report.skipped += 1 }
            }
        }
        let grouped = Dictionary(grouping: report.items, by: \.digest)
        report.duplicates = grouped.values.filter { $0.count > 1 }.map { $0.map(\.id) }
        let duplicateIDs = Set(report.duplicates.flatMap { $0 })
        for i in report.items.indices { report.items[i].duplicate = duplicateIDs.contains(report.items[i].id) }
        report.items.sort { $0.digest.bytes > $1.digest.bytes }
        return report
    }
    func delete(_ items: [FileItem], report: FileReport) throws -> [String] {
        guard SafetyPolicy.deletionAllowed(selected: Set(items.map(\.id)), known: Set(report.items.map(\.id)), duplicateGroups: report.duplicates) else {
            throw CleanerError.message("Оставьте один файл в каждой группе дубликатов.")
        }
        let selected = Set(items.map(\.id))
        for group in report.duplicates where !selected.isDisjoint(with: group) {
            var survivorExists = false
            for survivor in report.items where group.contains(survivor.id) && !selected.contains(survivor.id) {
                let scoped = survivor.root.startAccessingSecurityScopedResource()
                defer { if scoped { survivor.root.stopAccessingSecurityScopedResource() } }
                if survivor.url.resolvingSymlinksInPath().path == survivor.url.path,
                   let current = try? Self.fingerprint(survivor.url), current == survivor.digest { survivorExists = true; break }
            }
            guard survivorExists else { throw CleanerError.message("Сохраняемый дубликат изменён или недоступен. Повторите анализ.") }
        }
        var errors: [String] = []
        for item in items {
            let scoped = item.root.startAccessingSecurityScopedResource()
            defer { if scoped { item.root.stopAccessingSecurityScopedResource() } }
            do {
                guard item.url == item.root || SafetyPolicy.isInside(item.url, root: item.root),
                      item.url.resolvingSymlinksInPath().standardizedFileURL.path == item.url.standardizedFileURL.path else { throw CleanerError.message("Путь изменился") }
                var coordinationError: NSError?; var operationError: Error?
                NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinationError) { coordinated in
                    do {
                        let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true, values.contentModificationDate == item.modified,
                              try Self.fingerprint(coordinated) == item.digest else { throw CleanerError.message("Файл изменён; повторите сканирование") }
                        try FileManager.default.removeItem(at: coordinated)
                    } catch { operationError = error }
                }
                if let error = coordinationError ?? operationError as NSError? { throw error }
            } catch { errors.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return errors
    }
}

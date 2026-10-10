import Photos
import UIKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct PhotoItem: Identifiable {
    let id: String
    let date: Date?
    let modified: Date?
    let width: Int
    let height: Int
    let video: Bool
    let favorite: Bool
    let live: Bool
    let screenshot: Bool
    let digest: ContentDigest?
    let similarity: UInt64?
    let duration: TimeInterval
    var bytes: Int64 { digest?.bytes ?? 0 }
}
struct PhotoReport {
    var items: [PhotoItem] = []
    var duplicates: [[String]] = []
    var similar: [[String]] = []
    var unavailable = 0
}
// PhotoKit may deliver chunks on an internal queue. The lock protects incremental hashing.
private final class ResourceHasher: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()
    private var bytes: Int64 = 0
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; hasher.update(data: data); bytes += Int64(data.count) }
    func result() -> ContentDigest { lock.lock(); defer { lock.unlock() }; return .init(hash: hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes: bytes) }
}
actor PhotoService {
    static func resourceDigest(_ resource: PHAssetResource) async throws -> ContentDigest {
        let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = false
        let state = ResourceHasher()
        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { state.append($0) }, completionHandler: { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: state.result()) }
            })
        }
    }
    static func digest(_ asset: PHAsset) async throws -> ContentDigest {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw CleanerError.message("Нет локальных ресурсов") }
        var components: [String] = []; var total: Int64 = 0
        for resource in resources {
            try Task.checkCancellation()
            let digest = try await resourceDigest(resource)
            components.append("\(resource.type.rawValue):\(digest.bytes):\(digest.hash)")
            total += digest.bytes
        }
        return .init(hash: components.sorted().joined(separator: "|"), bytes: total)
    }
    static func image(_ id: String, size: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat; options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image)
            }
        }
    }
    private static func perceptualHash(_ image: UIImage) -> UInt64? {
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 72)
        let drawn = pixels.withUnsafeMutableBytes { pointer -> Bool in
            guard let ctx = CGContext(data: pointer.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 9, height: 8)); return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { if pixels[y*9+x] > pixels[y*9+x+1] { hash |= 1 << (y*8+x) } } }
        return hash
    }
    func scan(options: ScanOptions, progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> PhotoReport {
        let fetch = PHFetchOptions(); fetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: fetch)
        var report = PhotoReport(); var exact: [String: [String]] = [:]
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            let digest = try? await Self.digest(asset)
            try Task.checkCancellation()
            if digest == nil { report.unavailable += 1 }
            var hash: UInt64?
            if options.similar && asset.mediaType == .image, let image = await Self.image(asset.localIdentifier, size: CGSize(width: 160, height: 160)) { hash = Self.perceptualHash(image) }
            report.items.append(.init(id: asset.localIdentifier, date: asset.creationDate, modified: asset.modificationDate, width: asset.pixelWidth, height: asset.pixelHeight, video: asset.mediaType == .video, favorite: asset.isFavorite, live: asset.mediaSubtypes.contains(.photoLive), screenshot: asset.mediaSubtypes.contains(.photoScreenshot), digest: digest, similarity: hash, duration: asset.duration))
            if let digest { exact[digest.hash, default: []].append(asset.localIdentifier) }
            await progress(index+1, assets.count)
        }
        report.duplicates = exact.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
        // Nearby capture times bound comparisons; similarity is only a visual recommendation.
        if options.similar {
            var grouped: Set<String> = []
            for (i, item) in report.items.enumerated() where item.similarity != nil && !grouped.contains(item.id) {
                var group = [item.id]
                for other in report.items.dropFirst(i+1).prefix(100) {
                    guard let date = item.date, let next = other.date, abs(next.timeIntervalSince(date)) < 120,
                          let hash = other.similarity, !grouped.contains(other.id),
                          item.digest?.hash != other.digest?.hash,
                          (item.similarity! ^ hash).nonzeroBitCount <= 6 else { continue }
                    group.append(other.id)
                }
                if group.count > 1 { report.similar.append(group); grouped.formUnion(group) }
            }
        }
        return report
    }
    func delete(_ selected: [PhotoItem], report: PhotoReport) async throws {
        let ids = Set(selected.map(\.id))
        guard SafetyPolicy.deletionAllowed(selected: ids, known: Set(report.items.map(\.id)), duplicateGroups: report.duplicates), !selected.contains(where: \.favorite) else {
            throw CleanerError.message("Избранное защищено. Оставьте хотя бы один объект в каждой группе дубликатов.")
        }
        for group in report.duplicates where !ids.isDisjoint(with: group) {
            var survivorExists = false
            for keeper in report.items where group.contains(keeper.id) && !ids.contains(keeper.id) {
                if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [keeper.id], options: nil).firstObject,
                   let expected = keeper.digest, let current = try? await Self.digest(asset), current == expected { survivorExists = true; break }
            }
            guard survivorExists else { throw CleanerError.message("Сохраняемый оригинал недоступен или изменён. Повторите анализ.") }
        }
        var assets: [PHAsset] = []
        for item in selected {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject,
                  asset.modificationDate == item.modified, !asset.isFavorite,
                  let expected = item.digest, try await Self.digest(asset) == expected else {
                throw CleanerError.message("Объект изменён или недоступен локально. Выполните новое сканирование.")
            }
            assets.append(asset)
        }
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }
    }
    func optimize(_ item: PhotoItem, options: ScanOptions) async throws -> OptimizationPreview {
        guard !item.video, !item.live,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject,
              asset.modificationDate == item.modified,
              !asset.mediaSubtypes.contains(.photoHDR), !asset.mediaSubtypes.contains(.photoPanorama) else {
            throw CleanerError.message("Оптимизация доступна для обычных неподвижных фото. Live Photo, HDR и панорамы сохраняются без изменений.")
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.count == 1, let resource = resources.first,
              [UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(resource.uniformTypeIdentifier) else {
            throw CleanerError.message("RAW, отредактированные фото и составные ресурсы не преобразуются.")
        }
        guard item.bytes > 0 && item.bytes <= 100 * 1024 * 1024 else { throw CleanerError.message("Для оптимизации выберите локальное фото размером до 100 МБ.") }
        let request = PHImageRequestOptions(); request.isNetworkAccessAllowed = false; request.version = .original
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: request) { data, _, _, info in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? CleanerError.message("Оригинал недоступен локально")) }
            }
        }
        try Task.checkCancellation()
        let encoded = try PhotoEncoder.encode(data, options: options)
        return OptimizationPreview(sourceID: item.id, data: encoded, originalBytes: Int64(data.count), date: item.date)
    }
    func save(_ preview: OptimizationPreview) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: .photo, data: preview.data, options: nil)
            creation.creationDate = preview.date
        }
    }
}
struct OptimizationPreview: Identifiable {
    let id = UUID()
    let sourceID: String
    let data: Data
    let originalBytes: Int64
    let date: Date?
}

enum PhotoEncoder {
    static func encode(_ data: Data, options: ScanOptions) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:max(1024, min(options.maxPixel, 4096))] as CFDictionary) else { throw CleanerError.message("Не удалось прочитать фото") }
        let encoded = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { throw CleanerError.message("JPEG недоступен") }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality:max(0.6, min(options.jpegQuality, 0.95))] as CFDictionary)
        guard CGImageDestinationFinalize(output), SafetyPolicy.optimizationSavesSpace(original: Int64(data.count), output: Int64(encoded.length)) else {
            throw CleanerError.message("Экономия меньше 10%. Лучше сохранить исходное фото.")
        }
        return encoded as Data
    }
}

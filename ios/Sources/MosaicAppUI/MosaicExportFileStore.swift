import Foundation
import MosaicCore

public protocol MosaicExportFileManaging: Sendable {
    func destination(for projectID: UUID, format: MosaicExportFormat) async throws -> URL
    func record(_ result: MosaicExportResult, for project: MosaicProject) async throws
    func recover(for project: MosaicProject) async -> MosaicExportResult?
    func discardExport(for projectID: UUID) async
    func discardFile(at url: URL) async
    func purgeAbandonedFiles(olderThan cutoff: Date) async
    func purgeExpiredExports(olderThan cutoff: Date) async
}

public actor MosaicExportFileStore: MosaicExportFileManaging {
    private static let manifestVersion = 1
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosaicExports", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directory = directory.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public func destination(
        for projectID: UUID,
        format: MosaicExportFormat
    ) throws -> URL {
        try createDirectory()
        return directory.appendingPathComponent(
            "mosaic-\(projectID.uuidString)-\(UUID().uuidString).\(format.fileExtension)"
        )
    }

    public func record(_ result: MosaicExportResult, for project: MosaicProject) throws {
        try createDirectory()
        guard contains(result.url),
              let actualBytes = fileSize(at: result.url),
              actualBytes > 0,
              actualBytes == result.bytesWritten,
              result.width > 0,
              result.height > 0,
              result.pixelsPerInch > 0 else {
            throw MosaicExportFileStoreError.invalidCompletedFile
        }

        let previous = loadManifest(for: project.id)
        let manifest = Manifest(
            version: Self.manifestVersion,
            projectID: project.id,
            projectUpdatedAt: project.updatedAt,
            fileName: result.url.lastPathComponent,
            format: result.format,
            width: result.width,
            height: result.height,
            bytesWritten: actualBytes,
            pixelsPerInch: result.pixelsPerInch,
            createdAt: Date()
        )
        do {
            try encoder.encode(manifest).write(to: manifestURL(for: project.id), options: .atomic)
        } catch {
            throw MosaicExportFileStoreError.writeFailed
        }

        if let previous, previous.fileName != manifest.fileName {
            removeContainedFile(named: previous.fileName)
        }
    }

    public func recover(for project: MosaicProject) -> MosaicExportResult? {
        guard let manifest = loadManifest(for: project.id),
              manifest.version == Self.manifestVersion,
              manifest.projectID == project.id,
              abs(manifest.projectUpdatedAt.timeIntervalSince(project.updatedAt)) < 0.001,
              manifest.width > 0,
              manifest.height > 0,
              manifest.pixelsPerInch > 0,
              let format = manifest.exportFormat else {
            discardExport(for: project.id)
            return nil
        }
        let fileURL = directory.appendingPathComponent(manifest.fileName).standardizedFileURL
        guard contains(fileURL),
              fileURL.lastPathComponent == manifest.fileName,
              let actualBytes = fileSize(at: fileURL),
              actualBytes > 0,
              actualBytes == manifest.bytesWritten else {
            discardExport(for: project.id)
            return nil
        }
        return MosaicExportResult(
            url: fileURL,
            format: format,
            width: manifest.width,
            height: manifest.height,
            bytesWritten: actualBytes,
            pixelsPerInch: manifest.pixelsPerInch
        )
    }

    public func discardExport(for projectID: UUID) {
        if let manifest = loadManifest(for: projectID) {
            removeContainedFile(named: manifest.fileName)
        }
        try? fileManager.removeItem(at: manifestURL(for: projectID))
    }

    public func discardFile(at url: URL) {
        guard contains(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    public func purgeAbandonedFiles(olderThan cutoff: Date) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return }
        let retainedNames = Set(
            urls.filter { $0.pathExtension == "json" }
                .compactMap { try? decoder.decode(Manifest.self, from: Data(contentsOf: $0)) }
                .filter { $0.version == Self.manifestVersion }
                .map(\.fileName)
        )
        for url in urls where url.pathExtension != "json" && !retainedNames.contains(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  (values?.contentModificationDate ?? .distantPast) < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    public func purgeExpiredExports(olderThan cutoff: Date) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return }
        for manifestURL in urls where manifestURL.lastPathComponent.hasSuffix(".export.json") {
            if let manifest = try? decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL)) {
                guard manifest.createdAt < cutoff else { continue }
                removeContainedFile(named: manifest.fileName)
                try? fileManager.removeItem(at: manifestURL)
            } else {
                let modified = try? manifestURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if (modified ?? .distantPast) < cutoff {
                    try? fileManager.removeItem(at: manifestURL)
                }
            }
        }
    }

    private func createDirectory() throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw MosaicExportFileStoreError.writeFailed
        }
    }

    private func manifestURL(for projectID: UUID) -> URL {
        directory.appendingPathComponent("\(projectID.uuidString).export.json")
    }

    private func loadManifest(for projectID: UUID) -> Manifest? {
        try? decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL(for: projectID)))
    }

    private func contains(_ url: URL) -> Bool {
        let candidateParent = url.standardizedFileURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .path
        let managedDirectory = directory
            .resolvingSymlinksInPath()
            .path
        return candidateParent == managedDirectory
    }

    private func fileSize(at url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private func removeContainedFile(named fileName: String) {
        let url = directory.appendingPathComponent(fileName).standardizedFileURL
        guard contains(url), url.lastPathComponent == fileName else { return }
        try? fileManager.removeItem(at: url)
    }
}

public enum MosaicExportFileStoreError: Error, Equatable, Sendable {
    case invalidCompletedFile
    case writeFailed
}

private struct Manifest: Codable {
    let version: Int
    let projectID: UUID
    let projectUpdatedAt: Date
    let fileName: String
    let formatName: String
    let jpegQuality: Double?
    let width: Int
    let height: Int
    let bytesWritten: Int
    let pixelsPerInch: Int
    let createdAt: Date

    init(
        version: Int,
        projectID: UUID,
        projectUpdatedAt: Date,
        fileName: String,
        format: MosaicExportFormat,
        width: Int,
        height: Int,
        bytesWritten: Int,
        pixelsPerInch: Int,
        createdAt: Date
    ) {
        self.version = version
        self.projectID = projectID
        self.projectUpdatedAt = projectUpdatedAt
        self.fileName = fileName
        switch format {
        case .png:
            formatName = "png"
            jpegQuality = nil
        case .jpeg(let quality):
            formatName = "jpeg"
            jpegQuality = quality
        }
        self.width = width
        self.height = height
        self.bytesWritten = bytesWritten
        self.pixelsPerInch = pixelsPerInch
        self.createdAt = createdAt
    }

    var exportFormat: MosaicExportFormat? {
        switch formatName {
        case "png":
            return .png
        case "jpeg":
            guard let jpegQuality,
                  jpegQuality.isFinite,
                  (0...1).contains(jpegQuality) else { return nil }
            return .jpeg(quality: jpegQuality)
        default:
            return nil
        }
    }
}

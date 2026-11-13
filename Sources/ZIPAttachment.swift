import Foundation
import UniformTypeIdentifiers

struct ZIPAttachment {
    let url: URL
    let name: String

    static func load(from provider: NSItemProvider, into directory: URL) async throws -> Self {
        let zipTypes = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .zip) == true
        }
        for type in zipTypes {
            if let attachment = try? await loadFile(from: provider, type: type, into: directory) {
                return attachment
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let attachment = try? await loadFileURL(from: provider, into: directory) {
            return attachment
        }
        for type in provider.registeredTypeIdentifiers where !zipTypes.contains(type) {
            guard type != UTType.fileURL.identifier, UTType(type)?.conforms(to: .data) == true else {
                continue
            }
            if let attachment = try? await loadFile(from: provider, type: type, into: directory) {
                return attachment
            }
        }
        throw ZIPError.unreadableAttachment
    }

    private static func loadFile(
        from provider: NSItemProvider, type: String, into directory: URL
    ) async throws -> Self {
        let name = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                continuation.resume(with: Result {
                    guard let url else { throw error ?? ZIPError.unreadableAttachment }
                    // The provider can delete this temporary file as soon as the callback returns.
                    return try stage(url, suggestedName: name, into: directory)
                })
            }
        }
    }

    private static func loadFileURL(
        from provider: NSItemProvider, into directory: URL
    ) async throws -> Self {
        let name = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { item, error in
                continuation.resume(with: Result {
                    guard let url = item as? URL else { throw error ?? ZIPError.unreadableAttachment }
                    return try stage(url, suggestedName: name, into: directory)
                })
            }
        }
    }

    static func stage(_ source: URL, suggestedName: String?, into directory: URL) throws -> Self {
        guard source.isFileURL else { throw ZIPError.unreadableAttachment }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ZIPError.unreadableAttachment
        }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 4)
        let zipSignatures: [Data] = [Data([0x50, 0x4b, 3, 4]), Data([0x50, 0x4b, 5, 6])]
        guard let signature, zipSignatures.contains(signature) else {
            throw ZIPError.unreadableAttachment
        }

        let suggested = (suggestedName as NSString?)?.lastPathComponent
        let original = source.lastPathComponent
        let candidate = [suggested, original].compactMap { $0 }.first {
            !$0.isEmpty && !$0.hasPrefix(".") && !$0.contains(":") && !$0.contains("\0")
        } ?? "WeChat Chat"
        let name = (candidate as NSString).pathExtension.lowercased() == "zip"
            ? candidate : candidate + ".zip"
        let staged = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: staged)
        return Self(url: staged, name: name)
    }

    func save(to directory: URL) throws -> URL {
        let files = FileManager.default
        let temporaryDirectory = directory.appendingPathComponent(".WeChatSave-\(UUID())", isDirectory: true)
        try files.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: temporaryDirectory) }
        let temporaryFile = temporaryDirectory.appendingPathComponent("archive")
        try files.copyItem(at: url, to: temporaryFile)

        let stem = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        for index in 1...10_000 {
            let filename = index == 1 ? name : "\(stem) (\(index)).\(suffix)"
            let destination = directory.appendingPathComponent(filename)
            if renamex_np(temporaryFile.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                return destination
            }
            let code = errno
            guard code == EEXIST else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            }
        }
        throw ZIPError.nameUnavailable
    }
}

enum ZIPError: LocalizedError {
    case unreadableAttachment
    case nameUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadableAttachment: "没有收到可读取的 ZIP 文件。"
        case .nameUnavailable: "目标目录中已有太多同名 ZIP 文件。"
        }
    }
}

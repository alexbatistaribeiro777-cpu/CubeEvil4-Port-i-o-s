import Foundation

struct DiscInfo {
    let url: URL
    let size: Int64
    let gameID: String
    let format: String

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum DiscStoreError: LocalizedError {
    case notReadable
    case notAGameCubeImage
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReadable:
            return "Nao foi possivel ler o arquivo escolhido."
        case .notAGameCubeImage:
            return "O arquivo nao parece uma imagem de GameCube (ISO/GCM) nem um RVZ."
        case .copyFailed(let detail):
            return "A copia para o app falhou: \(detail)"
        }
    }
}

/// Copies disc images into the app's Documents folder.
///
/// A document picker URL is security scoped and may disappear when the picker
/// closes, so the bytes are copied once (like the Android import) and the core
/// only ever sees a stable path. The copies are excluded from iCloud backup.
final class DiscStore {
    private let fileManager = FileManager.default
    let directory: URL
    let dataDirectory: URL

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Discs", isDirectory: true)
        dataDirectory = documents.appendingPathComponent("Core", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func existingDisc(slot: Int) -> DiscInfo? {
        guard let url = files(for: slot).first else { return nil }
        return try? inspect(url)
    }

    func importDisc(slot: Int, from source: URL) throws -> DiscInfo {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let ext = source.pathExtension.isEmpty ? "iso" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("disc\(slot).\(ext)")

        for old in files(for: slot) {
            try? fileManager.removeItem(at: old)
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw DiscStoreError.copyFailed(error.localizedDescription)
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(values)

        return try inspect(destination)
    }

    private func files(for slot: Int) -> [URL] {
        let prefix = "disc\(slot)."
        let items = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func inspect(_ url: URL) throws -> DiscInfo {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw DiscStoreError.notReadable
        }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 0x40)) ?? Data()
        guard header.count >= 4 else {
            throw DiscStoreError.notAGameCubeImage
        }

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        // GameCube disc header: game ID at 0x00, magic word at 0x1C.
        if header.count >= 0x20 {
            let gameID = String(data: header.subdata(in: 0..<6), encoding: .ascii) ?? "??????"
            let magic = header.subdata(in: 0x1C..<0x20)
            if magic == Data([0xC2, 0x33, 0x9F, 0x3D]) {
                return DiscInfo(
                    url: url,
                    size: size,
                    gameID: gameID.trimmingCharacters(in: .whitespacesAndNewlines),
                    format: "ISO/GCM"
                )
            }
        }

        // RVZ (Dolphin compressed image) container.
        if header.prefix(4) == Data([0x52, 0x56, 0x5A, 0x01]) {
            return DiscInfo(url: url, size: size, gameID: "RVZ", format: "RVZ")
        }

        throw DiscStoreError.notAGameCubeImage
    }
}

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum NotchGlobalDropStripState: Equatable {
    enum RejectionReason: Equatable {
        case notesDisabled
        case unsupportedDrag
    }

    enum FailureReason: Equatable {
        case insertionFailed
        case partialFailure(failedCount: Int)
    }

    case inactive
    case hovering(fileCount: Int)
    case accepted(fileCount: Int)
    case rejected(reason: RejectionReason)
    case failed(reason: FailureReason)

    var isVisible: Bool {
        self != .inactive
    }

    var fileCount: Int {
        switch self {
        case .hovering(let fileCount), .accepted(let fileCount):
            return fileCount
        case .inactive, .rejected, .failed:
            return 0
        }
    }

    func message(language: AppLanguage) -> String {
        switch (language, self) {
        case (.zhHans, .hovering):
            return "拖到这里添加到最近 note"
        case (.english, .hovering):
            return "Drop here to add to recent note"
        case (.zhHans, .accepted):
            return "已添加到 note"
        case (.english, .accepted):
            return "Added to note"
        case (.zhHans, .rejected(.notesDisabled)):
            return "启用 Notes 后可添加文件"
        case (.english, .rejected(.notesDisabled)):
            return "Enable Notes to add files"
        case (.zhHans, .rejected(.unsupportedDrag)):
            return "只支持常见文件或图片"
        case (.english, .rejected(.unsupportedDrag)):
            return "Common files or images only"
        case (.zhHans, .failed(.partialFailure(let failedCount))):
            return "\(failedCount) 个文件添加失败"
        case (.english, .failed(.partialFailure(let failedCount))):
            return "\(failedCount) file\(failedCount == 1 ? "" : "s") failed"
        case (.zhHans, .failed(.insertionFailed)):
            return "添加到 note 失败"
        case (.english, .failed(.insertionFailed)):
            return "Could not add to note"
        case (_, .inactive):
            return ""
        }
    }

    func accessoryText(language: AppLanguage) -> String? {
        guard fileCount > 1 else {
            return nil
        }

        switch language {
        case .zhHans:
            return "\(fileCount) 个文件"
        case .english:
            return "\(fileCount) files"
        }
    }
}

struct NotchGlobalDragPasteboardSnapshot: Equatable {
    let changeCount: Int
    let supportedFileURLCount: Int
}

protocol NotchGlobalDragPasteboardReading {
    func snapshot() -> NotchGlobalDragPasteboardSnapshot
}

extension NotchGlobalDragPasteboardReading {
    func fileURLCount() -> Int {
        snapshot().supportedFileURLCount
    }
}

struct NotchGlobalDragPasteboardReader: NotchGlobalDragPasteboardReading {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> NotchGlobalDragPasteboardSnapshot {
        NotchGlobalDragPasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            supportedFileURLCount: NotchGlobalSupportedDropFile.supportedURLs(in: pasteboard).count
        )
    }
}

@MainActor
struct NotchGlobalDropHandler {
    var notesPlugin: () -> NotesPlugin?
    var selectNotes: () -> Void

    func hoveringState(fileCount: Int) -> NotchGlobalDropStripState {
        guard fileCount > 0 else {
            return .rejected(reason: .unsupportedDrag)
        }
        guard notesPlugin()?.isEnabled == true else {
            return .rejected(reason: .notesDisabled)
        }

        selectNotes()
        return .hovering(fileCount: fileCount)
    }

    func performDrop(urls: [URL]) -> NotchGlobalDropStripState {
        let supportedURLs = urls.filter(NotchGlobalSupportedDropFile.isSupported)
        let unsupportedCount = urls.count - supportedURLs.count
        guard supportedURLs.isEmpty == false else {
            return .rejected(reason: .unsupportedDrag)
        }
        guard let notesPlugin = notesPlugin(), notesPlugin.isEnabled else {
            return .rejected(reason: .notesDisabled)
        }

        do {
            let result = try notesPlugin.ingestDroppedFiles(supportedURLs)
            if result.insertedCount > 0 {
                selectNotes()
            }
            let failedCount = result.failedCount + unsupportedCount
            if failedCount > 0 {
                return .failed(reason: .partialFailure(failedCount: failedCount))
            }

            return .accepted(fileCount: result.insertedCount)
        } catch {
            return .failed(reason: .insertionFailed)
        }
    }
}

enum NotchGlobalSupportedDropFile {
    private static let supportedExtensions: Set<String> = [
        "7z",
        "bmp",
        "csv",
        "doc",
        "docx",
        "gif",
        "gz",
        "heic",
        "htm",
        "html",
        "jpeg",
        "jpg",
        "json",
        "key",
        "keynote",
        "log",
        "m4a",
        "markdown",
        "md",
        "mov",
        "mp3",
        "mp4",
        "numbers",
        "pages",
        "pdf",
        "png",
        "ppt",
        "pptx",
        "rar",
        "rtf",
        "rtfd",
        "tar",
        "tgz",
        "tif",
        "tiff",
        "txt",
        "wav",
        "webp",
        "xls",
        "xlsx",
        "xml",
        "yaml",
        "yml",
        "zip",
    ]
    private static let supportedPackageExtensions: Set<String> = [
        "key",
        "keynote",
        "numbers",
        "pages",
        "rtfd",
    ]

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    static func supportedURLs(in pasteboard: NSPasteboard) -> [URL] {
        supportedURLs(from: fileURLs(in: pasteboard))
    }

    static func supportedURLs(from urls: [URL]) -> [URL] {
        urls.filter(isSupported)
    }

    static func isSupported(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(pathExtension),
              isRegularFileOrSupportedPackage(url, pathExtension: pathExtension)
        else {
            return false
        }

        return true
    }

    private static func isRegularFileOrSupportedPackage(_ url: URL, pathExtension: String) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey])
        if values?.isRegularFile == true {
            return true
        }
        if values?.isDirectory == true {
            return supportedPackageExtensions.contains(pathExtension)
        }
        if values?.isPackage == true {
            return supportedPackageExtensions.contains(pathExtension)
        }
        return false
    }
}

@MainActor
enum NotchGlobalDragReducer {
    static func state(
        eventType: NSEvent.EventType,
        fileURLCount: Int,
        currentState: NotchGlobalDropStripState,
        handler: NotchGlobalDropHandler
    ) -> NotchGlobalDropStripState? {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if fileURLCount > 0 {
                return handler.hoveringState(fileCount: fileURLCount)
            }
            return currentState.clearsWhenGlobalDragEnds ? .inactive : nil
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return currentState.clearsWhenGlobalDragEnds ? .inactive : nil
        default:
            return nil
        }
    }

    static func shouldInspectPasteboard(for eventType: NSEvent.EventType) -> Bool {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}

private extension NotchGlobalDropStripState {
    var clearsWhenGlobalDragEnds: Bool {
        switch self {
        case .hovering, .rejected:
            return true
        case .inactive, .accepted, .failed:
            return false
        }
    }
}

struct NotchGlobalFileDropDelegate: DropDelegate {
    var handler: NotchGlobalDropHandler
    var onStateChange: (NotchGlobalDropStripState) -> Void
    var onDropCompleted: (NotchGlobalDropStripState) -> Void
    var supportedFileCount: () -> Int = {
        NotchGlobalDragPasteboardReader().fileURLCount()
    }

    func validateDrop(info: DropInfo) -> Bool {
        fileProviders(in: info).isEmpty == false && supportedFileCount() > 0
    }

    func dropEntered(info: DropInfo) {
        onStateChange(dropState(info: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let state = dropState(info: info)
        switch state {
        case .hovering:
            return DropProposal(operation: .copy)
        case .inactive, .accepted, .failed, .rejected:
            return DropProposal(operation: .forbidden)
        }
    }

    func dropExited(info: DropInfo) {
        onStateChange(.inactive)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = fileProviders(in: info)
        guard providers.isEmpty == false else {
            onDropCompleted(.rejected(reason: .unsupportedDrag))
            return false
        }

        Self.loadFileURLs(from: providers) { urls in
            Task { @MainActor in
                onDropCompleted(handler.performDrop(urls: urls))
            }
        }
        return true
    }

    private func fileProviders(in info: DropInfo) -> [NSItemProvider] {
        info.itemProviders(for: [UTType.fileURL.identifier])
    }

    private func dropState(info: DropInfo) -> NotchGlobalDropStripState {
        guard fileProviders(in: info).isEmpty == false else {
            return .rejected(reason: .unsupportedDrag)
        }
        return handler.hoveringState(fileCount: supportedFileCount())
    }

    private static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let group = DispatchGroup()
        let accumulator = NotchGlobalDropURLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                accumulator.append(url)
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.urls)
        }
    }
}

private final class NotchGlobalDropURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        values.append(url)
    }
}

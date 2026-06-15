import AppKit
import SwiftUI

struct ScratchpadMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void
    var onDroppedFiles: ([URL]) -> Void
    var onPastedImages: ([NSImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ScratchpadMarkdownScrollView {
        let scrollView = ScratchpadMarkdownScrollView()
        scrollView.onDroppedFiles = onDroppedFiles
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ScratchpadMarkdownTextView()
        textView.delegate = context.coordinator
        textView.onPastedImages = onPastedImages
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: ScratchpadMarkdownScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.onDroppedFiles = onDroppedFiles
        guard let textView = scrollView.documentView as? ScratchpadMarkdownTextView else {
            return
        }
        textView.onPastedImages = onPastedImages
        if textView.hasMarkedText() == false, textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadMarkdownEditor

        init(parent: ScratchpadMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
            parent.onTextChange(textView.string)
        }
    }
}

final class ScratchpadMarkdownTextView: NSTextView {
    var onPastedImages: ([NSImage]) -> Void = { _ in }

    override func paste(_ sender: Any?) {
        let images = NSPasteboard.general.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage] ?? []

        if images.isEmpty == false {
            onPastedImages(images)
            return
        }

        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }
}

final class ScratchpadMarkdownScrollView: NSScrollView {
    var onDroppedFiles: ([URL]) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedFileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedFileURLs(from: sender)
        guard urls.isEmpty == false else {
            return false
        }
        onDroppedFiles(urls)
        return true
    }

    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        NotchGlobalSupportedDropFile.supportedURLs(in: sender.draggingPasteboard)
    }
}

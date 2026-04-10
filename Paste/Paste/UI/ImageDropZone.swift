import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageDropZone: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onImage: (NSImage) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DropTargetView()
        view.onTargetedChanged = { targeted in
            isTargeted = targeted
        }
        view.onImage = onImage
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DropTargetView: NSView {
    var onTargetedChanged: ((Bool) -> Void)?
    var onImage: ((NSImage) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetedChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetedChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetedChanged?(false) }
        let pasteboard = sender.draggingPasteboard

        if let image = NSImage(pasteboard: pasteboard) {
            onImage?(image)
            return true
        }

        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]

        guard let urls = pasteboard.readObjects(forClasses: classes, options: options) as? [URL],
              let url = urls.first,
              let image = NSImage(contentsOf: url) else {
            return false
        }

        onImage?(image)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onTargetedChanged?(false)
    }
}

import AppKit
import SwiftData

@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var container: ModelContainer?
    var onCapture: ((String) -> Void)?
    var onRunningStateChanged: ((Bool) -> Void)?

    func start(container: ModelContainer) {
        stop()
        self.container = container
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onRunningStateChanged?(true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        container = nil
        onRunningStateChanged?(false)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        guard let container else {
            return
        }

        let context = ModelContext(container)
        let store = ClipStore(context: context)
        if let summary = try? store.ingestClipboardIfNeeded(changeCount: pasteboard.changeCount) {
            onCapture?(summary)
        }
    }
}

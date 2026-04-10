import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = AppSettings()
    @Published var isClipboardMonitoringRunning = false
    @Published var lastClipboardCaptureMessage: String?

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let clipboardMonitor = ClipboardMonitor()
    private var container: ModelContainer?
    private var outsideClickMonitor: Any?

    func configure(container: ModelContainer) {
        self.container = container
    }

    var currentPopoverHeight: CGFloat {
        let liveHeight = popover.contentSize.height
        return liveHeight > 0 ? liveHeight : settings.panelHeight
    }

    func updatePopoverHeight(_ height: CGFloat) {
        let clamped = min(max(height, 460), 900)
        if popover.contentSize.height != clamped {
            popover.contentSize = NSSize(width: popover.contentSize.width, height: clamped)
        }
    }

    func persistPopoverHeight() {
        let clamped = min(max(popover.contentSize.height, 460), 900)
        if settings.panelHeight != clamped {
            settings.panelHeight = clamped
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeSettings()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            stopOutsideClickMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            startOutsideClickMonitor()
        }
    }

    @objc func openSettings(_ sender: AnyObject?) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Aha paste")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.appearsDisabled = false
        if item.button?.image == nil {
            item.button?.title = "A"
        }
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
    }

    private func setupPopover() {
        guard let container else {
            return
        }

        // Keep the popover open while dragging content from other apps into it.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 396, height: settings.panelHeight)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environmentObject(settings)
                .environmentObject(self)
                .modelContainer(container)
        )
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else {
            return
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverFromOutsideInteraction()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func closePopoverFromOutsideInteraction() {
        guard popover.isShown else {
            stopOutsideClickMonitor()
            return
        }

        popover.performClose(nil)
        stopOutsideClickMonitor()
    }

    private func observeSettings() {
        clipboardMonitor.onRunningStateChanged = { [weak self] isRunning in
            self?.isClipboardMonitoringRunning = isRunning
        }
        clipboardMonitor.onCapture = { [weak self] message in
            self?.lastClipboardCaptureMessage = message
        }

        settings.onClipboardMonitoringChanged = { [weak self] enabled in
            guard let self, let container = self.container else {
                return
            }

            if enabled {
                self.lastClipboardCaptureMessage = nil
                self.clipboardMonitor.start(container: container)
            } else {
                self.clipboardMonitor.stop()
            }
        }

        // Restore clipboard monitoring on launch when the user previously enabled it.
        if settings.isClipboardMonitoringEnabled, let container = self.container {
            clipboardMonitor.start(container: container)
        }
    }
}

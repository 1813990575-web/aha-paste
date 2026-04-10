import Foundation

final class AppSettings: ObservableObject {
    enum CopySound: String, Identifiable {
        case frog

        var id: String { rawValue }

        var title: String {
            "Frog"
        }
    }

    @Published var panelHeight: Double {
        didSet {
            let clamped = min(max(panelHeight, 460), 900)
            if clamped != panelHeight {
                panelHeight = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.panelHeightKey)
        }
    }

    @Published var isClipboardMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isClipboardMonitoringEnabled, forKey: Self.monitoringKey)
            onClipboardMonitoringChanged?(isClipboardMonitoringEnabled)
        }
    }

    @Published var isSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: Self.soundKey)
        }
    }

    @Published var selectedCopySound: CopySound {
        didSet {
            UserDefaults.standard.set(selectedCopySound.rawValue, forKey: Self.copySoundKey)
        }
    }

    var onClipboardMonitoringChanged: ((Bool) -> Void)?

    private static let monitoringKey = "settings.clipboardMonitoringEnabled"
    private static let panelHeightKey = "settings.panelHeight"
    private static let soundKey = "settings.soundEnabled"
    private static let copySoundKey = "settings.copySound"

    init() {
        isClipboardMonitoringEnabled = UserDefaults.standard.bool(forKey: Self.monitoringKey)
        let savedHeight = UserDefaults.standard.double(forKey: Self.panelHeightKey)
        panelHeight = savedHeight == 0 ? 540 : savedHeight
        if UserDefaults.standard.object(forKey: Self.soundKey) == nil {
            isSoundEnabled = true
        } else {
            isSoundEnabled = UserDefaults.standard.bool(forKey: Self.soundKey)
        }
        let rawSound = UserDefaults.standard.string(forKey: Self.copySoundKey)
        selectedCopySound = CopySound(rawValue: rawSound ?? "") ?? .frog
    }
}

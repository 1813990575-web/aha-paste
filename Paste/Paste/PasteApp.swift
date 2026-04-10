import SwiftData
import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        container = ModelContainerFactory.shared.container
        appDelegate.configure(container: container)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .frame(width: 380)
                .modelContainer(container)
        }
    }
}

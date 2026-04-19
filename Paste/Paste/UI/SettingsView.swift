import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var pendingImportURL: URL?
    @State private var dataActionMessage: String?
    @State private var isImportAlertPresented = false

    var body: some View {
        Form {
            Section("行为") {
                Toggle("复制时播放音效", isOn: $settings.isSoundEnabled)

                Toggle(isOn: $settings.isClipboardMonitoringEnabled) {
                    SettingsHelpLabel(
                        title: "自动复制系统剪贴板",
                        helpText: "默认关闭。开启后，新的文本或图片剪贴板内容会自动写入历史。"
                    )
                }

                if settings.isClipboardMonitoringEnabled {
                    Text(appDelegate.isClipboardMonitoringRunning ? "当前状态：正在监听" : "当前状态：未运行")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appDelegate.isClipboardMonitoringRunning ? Color.green : Color.secondary)

                    if let lastMessage = appDelegate.lastClipboardCaptureMessage {
                        Text(lastMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("开启后，请复制一段新的文字或图片。捕获成功会在这里显示。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $settings.isAutomaticUpdateCheckEnabled) {
                    SettingsHelpLabel(
                        title: "自动检查更新",
                        helpText: "默认开启。发现新版本时，会提醒你前往 GitHub 下载。"
                    )
                }

                Button("立即检查更新") {
                    Task {
                        await appDelegate.checkForUpdates(isManual: true)
                    }
                }

                if let updateMessage = appDelegate.lastUpdateCheckMessage {
                    Text(updateMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("数据") {
                Button("导出数据…") {
                    exportData()
                }

                Button {
                    chooseImportArchive()
                } label: {
                    SettingsHelpLabel(
                        title: "导入数据…",
                        helpText: "导入会覆盖当前数据，导入完成后请退出并重新打开应用。"
                    )
                }

                if let dataActionMessage {
                    Text(dataActionMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("导入会覆盖当前数据", isPresented: $isImportAlertPresented, presenting: pendingImportURL) { url in
            Button("取消", role: .cancel) {
                pendingImportURL = nil
            }
            Button("导入并覆盖", role: .destructive) {
                importData(from: url)
            }
        } message: { _ in
            Text("建议先执行一次“导出数据”。导入后请手动退出并重新打开 Aha paste。")
        }
        .padding(20)
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "aha-paste-backup-\(Self.timestampFormatter.string(from: .now)).zip"

        guard panel.runModal() == .OK, let targetURL = panel.url else {
            return
        }

        do {
            let result = try DataBackupService.shared.exportBackup(to: targetURL)
            dataActionMessage = "已导出：\(result.archiveName)"
        } catch {
            dataActionMessage = error.localizedDescription
        }
    }

    private func chooseImportArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        pendingImportURL = selectedURL
        isImportAlertPresented = true
    }

    private func importData(from url: URL) {
        do {
            let result = try DataBackupService.shared.importBackup(from: url)
            dataActionMessage = "导入完成：\(result.archiveName)。请退出并重新打开应用。"
        } catch {
            dataActionMessage = error.localizedDescription
        }
        pendingImportURL = nil
    }
}

private struct SettingsHelpLabel: View {
    let title: String
    let helpText: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .help(helpText)
        }
    }
}

private extension SettingsView {
    static var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}

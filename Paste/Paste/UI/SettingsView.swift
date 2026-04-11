import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        Form {
            Section("行为") {
                Toggle("复制时播放音效", isOn: $settings.isSoundEnabled)

                Toggle("自动复制系统剪贴板", isOn: $settings.isClipboardMonitoringEnabled)
                Text("默认关闭。开启后，新的文本或图片剪贴板内容会自动写入历史。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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

                Toggle("自动检查更新", isOn: $settings.isAutomaticUpdateCheckEnabled)
                Text("默认开启。发现新版本时，会提醒你前往 GitHub 下载。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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
        }
        .padding(20)
    }
}

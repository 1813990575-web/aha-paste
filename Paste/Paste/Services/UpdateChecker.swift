import AppKit
import Foundation

struct ReleaseInfo: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateCheckResult {
    case updateAvailable(ReleaseInfo)
    case upToDate
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case missingVersion

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新信息获取失败，请稍后再试。"
        case .missingVersion:
            return "当前应用版本读取失败。"
        }
    }
}

final class UpdateChecker {
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/1813990575-web/aha-paste/releases/latest")!

    func checkForUpdates() async throws -> UpdateCheckResult {
        let (data, response) = try await URLSession.shared.data(from: latestReleaseURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }

        let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        let latestVersion = normalizedVersion(from: release.tagName)

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            throw UpdateCheckError.missingVersion
        }

        if compareVersion(latestVersion, to: currentVersion) == .orderedDescending {
            return .updateAvailable(release)
        }

        return .upToDate
    }

    func presentUpdateAlert(for release: ReleaseInfo) {
        let version = normalizedVersion(from: release.tagName)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(version)"
        alert.informativeText = "点击“前往下载”后，会打开 GitHub 发布页下载最新版本。"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func normalizedVersion(from rawValue: String) -> String {
        rawValue.replacingOccurrences(of: #"^[Vv]"#, with: "", options: .regularExpression)
    }

    private func compareVersion(_ lhs: String, to rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<count {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }
}

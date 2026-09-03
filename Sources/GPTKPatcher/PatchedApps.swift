import Foundation

/// A CrossOver that this app has patched, found by its receipt file.
struct PatchedApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let gptkVersion: String
    let patchedAt: Date?

    var id: String { url.path }
    var globalConfig: URL { url.appendingPathComponent("Contents/SharedSupport/CrossOver/etc/CrossOver.conf") }
    var folderDescription: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Remembers patched apps between launches and also discovers them in the usual app folders.
enum PatchedAppRegistry {
    private static let key = "patchedApps"
    static let receiptPath = "Contents/SharedSupport/CrossOver/gptkpatcher-receipt.json"

    static func remember(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        let path = url.standardizedFileURL.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func forget(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func load() -> [PatchedApp] {
        let fm = FileManager.default
        var candidates: [URL] = (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
        let home = fm.homeDirectoryForCurrentUser
        for folder in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasSuffix(".app") && name.localizedCaseInsensitiveContains("crossover") {
                candidates.append(folder.appendingPathComponent(name))
            }
        }
        var seen = Set<String>()
        var apps: [PatchedApp] = []
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            guard let app = read(url) else { continue }
            apps.append(app)
        }
        // Drop remembered entries that no longer exist.
        UserDefaults.standard.set(apps.map(\.url.path), forKey: key)
        return apps
    }

    private static func read(_ url: URL) -> PatchedApp? {
        let receipt = url.appendingPathComponent(receiptPath)
        guard let data = try? Data(contentsOf: receipt),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bundle = try? CrossOverBundle(url: url) else { return nil }
        let version = (json["gptkD3DMetalVersion"] as? String) ?? bundle.installedD3DMetalVersion ?? "?"
        let date = (json["date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return PatchedApp(url: url, name: bundle.name, gptkVersion: version, patchedAt: date)
    }
}

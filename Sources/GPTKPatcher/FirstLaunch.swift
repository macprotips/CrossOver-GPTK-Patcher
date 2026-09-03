import AppKit
import Foundation

/// macOS verifies a downloaded app the first time it opens and records the approval on it. A patched
/// bundle can't pass that check, so an app that has never been opened must be opened for real
/// before it is patched. This runs on the job's thread and blocks until CrossOver has been opened,
/// verified by macOS, and quit again.
enum FirstLaunch {
    /// Returns the app's location afterwards, which changes if CrossOver moved itself.
    static func approve(_ bundle: CrossOverBundle, token: CancellationToken, log: (String) -> Void) throws -> URL {
        guard bundle.needsFirstLaunch else { return bundle.url }
        let fm = FileManager.default
        let name = bundle.url.lastPathComponent
        log("\(name) hasn't been opened yet. Opening it so macOS can verify it; click Open if macOS asks.")

        // Launch. The completion fires once the user has answered macOS's prompt.
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: bundle.url, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now() + 0.25) == .timedOut { try token.checkpoint() }
        if let launchError {
            throw PatchError.io("macOS didn't open \(name): \(launchError.localizedDescription). Click Open when macOS asks, then try again.")
        }

        // Quit as soon as macOS has recorded the approval and the app is up. If CrossOver moves itself
        // to Applications and relaunches, the original path disappears; wait for the new process then.
        log("CrossOver is open. Quitting it as soon as macOS has verified it…")
        let deadline = Date().addingTimeInterval(300)
        var settled: NSRunningApplication?
        var launched = Date.distantFuture
        while Date() < deadline {
            try token.checkpoint()
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle.identifier)
                .filter { $0.isFinishedLaunching && !$0.isTerminated }
            let now = Date()
            if !apps.isEmpty, launched == .distantFuture { launched = now }
            let stillHere = fm.fileExists(atPath: bundle.url.path)
            let approved = stillHere ? ((try? CrossOverBundle(url: bundle.url))?.needsFirstLaunch == false) : true
            if let app = apps.first, approved, now.timeIntervalSince(launched) >= (stillHere ? 0.5 : 2) {
                settled = app
                break
            }
            if apps.isEmpty, launched != .distantFuture, now.timeIntervalSince(launched) > 5 {
                break   // it ran and was quit already; that counts too
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if let settled {
            log("Quitting CrossOver…")
            settled.terminate()
            let quitDeadline = Date().addingTimeInterval(3)
            while !settled.isTerminated, Date() < quitDeadline { Thread.sleep(forTimeInterval: 0.2) }
            if !settled.isTerminated {
                settled.forceTerminate()
                while !settled.isTerminated { Thread.sleep(forTimeInterval: 0.2) }
            }
        }

        // Find the app again; CrossOver may have moved itself.
        var location = bundle.url
        if !fm.fileExists(atPath: location.path) {
            let folders = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            guard let moved = folders.map({ $0.appendingPathComponent(name) }).first(where: { fm.fileExists(atPath: $0.path) }) else {
                throw PatchError.io("\(name) is no longer at \(bundle.url.deletingLastPathComponent().path). Drop it in again from its new location.")
            }
            log("\(name) moved itself to \(moved.deletingLastPathComponent().path); continuing there.")
            location = moved
        }
        let after = try CrossOverBundle(url: location)
        guard !after.needsFirstLaunch else {
            throw PatchError.io("macOS didn't record approval for \(name). Click Open when macOS asks, let CrossOver appear, then try again.")
        }
        log("macOS verified \(name).")
        return location
    }
}

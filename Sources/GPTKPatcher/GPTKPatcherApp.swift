import SwiftUI

/// Receives files dropped on the app icon or opened with the app and routes them to the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls { PatchEngine.shared.route(url) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct GPTKPatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Shows a window and takes focus even when launched as a bare executable.
        NSApplication.shared.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--cli") {
            HeadlessRunner.runAndExit()
        }
    }

    var body: some Scene {
        // A single window. Files opened via the Dock or Finder are routed into it.
        Window("CrossOver GPTK Patcher", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// `GPTKPatcher --cli --quit-bottle <name>` ends everything running in that bottle; `--bottle-status <name>` only lists it.
/// `GPTKPatcher --cli <CrossOver.app> <toolkit.dmg | version> [destination.app] [--in-place] [--replace] [--fps N] [--hud] [--no-copy-env] [--bottle NAME]...`
/// Runs the same job without the window, for scripting and testing.
enum HeadlessRunner {
    private static func quitBottleAndExit(named name: String, dryRun: Bool) -> Never {
        guard let bottle = BottleEnv.listBottles().first(where: { $0.name == name }) else {
            FileHandle.standardError.write(Data("error: no bottle named \(name)\n".utf8)); exit(1)
        }
        guard let running = BottleEnv.runningBottle(for: bottle) else { print("Nothing from the \(name) bottle is running."); exit(0) }
        print("\(dryRun ? "Running in" : "Ending") \(name): server \(running.serverPID.map(String.init) ?? "none"), \(running.clientPIDs.count) program(s)\(running.isStale ? ", stale session" : "") — pids \(running.clientPIDs.map(String.init).joined(separator: " "))")
        if dryRun { exit(0) }
        do { try BottleEnv.quit(running) } catch { FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); exit(1) }
        if let left = BottleEnv.runningBottle(for: bottle) { print("Still running: \(left.clientPIDs.count) program(s)"); exit(2) }
        print("Done. Nothing from the \(name) bottle is running.")
        exit(0)
    }

    static func runAndExit() -> Never {
        var args = Array(CommandLine.arguments.dropFirst())
        args.removeAll { $0 == "--cli" }
        if let index = args.firstIndex(of: "--quit-bottle"), index + 1 < args.count {
            quitBottleAndExit(named: args[index + 1], dryRun: false)
        }
        if let index = args.firstIndex(of: "--bottle-status"), index + 1 < args.count {
            quitBottleAndExit(named: args[index + 1], dryRun: true)
        }
        var replace = false
        var inPlace = false
        var hud = false
        var fps: Int? = nil
        var storeInCopy = true
        var bottleNames: [String] = []
        var positional: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--replace": replace = true
            case "--in-place": inPlace = true
            case "--hud": hud = true
            case "--no-copy-env": storeInCopy = false
            case "--fps":
                i += 1
                if i < args.count { fps = Int(args[i]) }
            case "--bottle":
                i += 1
                if i < args.count { bottleNames.append(args[i]) }
            default: positional.append(args[i])
            }
            i += 1
        }
        guard positional.count == (inPlace ? 2 : 3) else {
            FileHandle.standardError.write(Data("usage: GPTKPatcher --cli <CrossOver.app> <toolkit.dmg | version> [destination.app] [--in-place] [--replace] [--fps N] [--hud] [--no-copy-env] [--bottle NAME]...\n".utf8))
            exit(64)
        }
        do {
            let crossOver = try CrossOverBundle(url: URL(fileURLWithPath: positional[0]))
            if crossOver.needsFirstLaunch {
                print("note: \(crossOver.url.lastPathComponent) has never been opened; macOS may report the patched app as damaged. Open it once first, or patch from the app, which does that for you.")
            }
            let toolkitArg = positional[1]
            let toolkit: Toolkit
            if toolkitArg.lowercased().hasSuffix(".dmg") {
                toolkit = try ToolkitLibrary.importImage(URL(fileURLWithPath: toolkitArg)) { print($0) }
            } else if let stored = ToolkitLibrary.list().first(where: { $0.version == toolkitArg || $0.displayName == toolkitArg }) {
                toolkit = stored
            } else {
                let known = ToolkitLibrary.list().map(\.version).joined(separator: ", ")
                throw PatchError.io("No toolkit named \(toolkitArg) in the library\(known.isEmpty ? "" : " (have: \(known))"). Pass a .dmg to import one.")
            }
            let bottles = BottleEnv.listBottles().filter { bottleNames.contains($0.name) }
            let missing = Set(bottleNames).subtracting(bottles.map(\.name))
            if !missing.isEmpty { throw PatchError.io("Unknown bottle(s): \(missing.sorted().joined(separator: ", "))") }
            let applications = FileManager.default.isWritableFile(atPath: "/Applications")
                ? URL(fileURLWithPath: "/Applications", isDirectory: true)
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            let request = PatchRequest(
                crossOver: crossOver, toolkit: toolkit, mode: inPlace ? .inPlace : .copy,
                destination: URL(fileURLWithPath: inPlace ? positional[0] : positional[2]),
                applicationsFolder: applications,
                replaceExisting: replace,
                graphics: GraphicsSettings(fpsCap: fps, metalHUD: hud, storeInCopy: storeInCopy),
                bottles: bottles)
            let result = try PatchJob(request: request) { print($0) }.run()
            PatchedAppRegistry.remember(result)
            print(result.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

import Foundation

/// Finds command-line tools (yt-dlp, ffmpeg) the app needs.
///
/// Lookup order:
///   1. an explicit path the user picked ("Указать…")
///   2. binaries bundled inside the .app (`Contents/Resources/bin`)
///   3. the usual Homebrew / manual install locations
///   4. `which` with a broadened PATH
///
/// GUI apps launched from Finder don't inherit the shell `PATH`, hence the
/// hard-coded directory probing.
enum ToolLocator {

    static let searchDirs: [String] = [
        "/opt/homebrew/bin",              // Homebrew on Apple Silicon
        "/usr/local/bin",                 // Homebrew on Intel / manual installs
        "/opt/local/bin",                 // MacPorts
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/bin",
        "/usr/bin",
    ]

    /// Directory of the binaries shipped inside the app bundle, if present.
    static var bundledBinDirectory: String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let dir = resources.appendingPathComponent("bin", isDirectory: true).path
        return FileManager.default.fileExists(atPath: dir) ? dir : nil
    }

    /// True if `path` points at a binary we ship inside the bundle.
    static func isBundled(_ path: String) -> Bool {
        guard let bundled = bundledBinDirectory else { return false }
        return path.hasPrefix(bundled + "/")
    }

    /// Returns an absolute path to `name`, or nil if it can't be found.
    /// `userOverride` (an explicit path the user picked) wins if it's valid.
    static func find(_ name: String, userOverride: String?) -> String? {
        let fm = FileManager.default

        if let override = userOverride,
           !override.isEmpty,
           fm.isExecutableFile(atPath: override) {
            return override
        }

        if let bundled = bundledBinDirectory {
            let candidate = "\(bundled)/\(name)"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        for dir in searchDirs {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return whichFallback(name)
    }

    private static func whichFallback(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchDirs + ["/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        process.environment = env

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }

        return path
    }
}

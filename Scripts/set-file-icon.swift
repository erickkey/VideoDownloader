// Applies a custom Finder icon (from a PNG) to a target file.
// Usage: swift Scripts/set-file-icon.swift <icon.png> <target-path>

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: set-file-icon <icon.png> <target-path>")
    exit(1)
}
let iconPath = args[1]
let targetPath = args[2]

guard let image = NSImage(contentsOfFile: iconPath) else {
    print("could not load icon image at \(iconPath)")
    exit(1)
}

let ok = NSWorkspace.shared.setIcon(image, forFile: targetPath, options: [])
print(ok ? "icon set on \(targetPath)" : "FAILED to set icon on \(targetPath)")
exit(ok ? 0 : 1)

import SwiftUI

@main
struct YouTubeDownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 580, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}

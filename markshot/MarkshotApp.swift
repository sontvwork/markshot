import KeyboardShortcuts
import SwiftUI

@main
struct MarkshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("markshot", systemImage: "camera.viewfinder") {
            Button("Chụp vùng chọn") { CaptureCoordinator.shared.start(.region) }
                .globalKeyboardShortcut(.captureRegion)
            // M4
            Button("Chụp toàn màn hình") {}
                .globalKeyboardShortcut(.captureScreen)
                .disabled(true)
            Button("Chụp nhiều màn hình") {}
                .globalKeyboardShortcut(.captureAllScreens)
                .disabled(true)
            Divider()
            // M3
            Button("Preferences…") {}
                .disabled(true)
            Divider()
            Button("Quit markshot") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyDown(for: .captureRegion) {
            CaptureCoordinator.shared.start(.region)
        }
    }
}

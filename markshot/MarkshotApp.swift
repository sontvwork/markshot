import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
struct MarkshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("markshot", systemImage: "camera.viewfinder") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}

private struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
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
        Button("Preferences…") {
            openSettings()
            SettingsWindow.bringToFront()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit markshot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyDown(for: .captureRegion) {
            CaptureCoordinator.shared.start(.region)
        }

        // "Tự chạy khi đăng nhập" mặc định bật: đăng ký một lần ở lần chạy đầu tiên.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Prefs.Key.didSetupLoginItem) {
            defaults.set(true, forKey: Prefs.Key.didSetupLoginItem)
            try? SMAppService.mainApp.register()
        }
    }
}

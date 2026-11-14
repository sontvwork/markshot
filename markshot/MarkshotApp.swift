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
        Button("Chụp toàn màn hình") { CaptureCoordinator.shared.start(.screen) }
            .globalKeyboardShortcut(.captureScreen)
        Button("Chụp nhiều màn hình") { CaptureCoordinator.shared.start(.allScreens) }
            .globalKeyboardShortcut(.captureAllScreens)
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
        KeyboardShortcuts.onKeyDown(for: .captureScreen) {
            CaptureCoordinator.shared.start(.screen)
        }
        KeyboardShortcuts.onKeyDown(for: .captureAllScreens) {
            CaptureCoordinator.shared.start(.allScreens)
        }

        // Lấy sẵn danh sách màn hình để lần chụp đầu hiện overlay nhanh; lấy lại khi cắm/rút màn hình.
        ScreenCapturer.warmUp()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // "Tự chạy khi đăng nhập" mặc định bật: đăng ký một lần ở lần chạy đầu tiên.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Prefs.Key.didSetupLoginItem) {
            defaults.set(true, forKey: Prefs.Key.didSetupLoginItem)
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func screensChanged() {
        ScreenCapturer.invalidate()
    }
}

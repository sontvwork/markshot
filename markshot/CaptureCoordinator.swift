import AppKit
import os

enum CaptureMode {
    case region, screen, allScreens
}

/// Điểm vào của mọi lần chụp. Mỗi lúc chỉ giữ một phiên chụp.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var session: OverlaySession?
    private var busy = false

    func start(_ mode: CaptureMode) {
        guard session == nil, !busy else { return }
        busy = true
        guard CGPreflightScreenCaptureAccess() else {
            showPermissionAlert()
            busy = false
            return
        }

        let started = ContinuousClock.now
        Task {
            defer { busy = false }
            do {
                let shots = try await ScreenCapturer.capture(NSScreen.screens)
                guard !shots.isEmpty else { return }
                session = OverlaySession(shots: shots) { self.session = nil }
                #if DEBUG
                Logger(subsystem: "com.son.markshot", category: "timing")
                    .notice("overlay hiện sau \(started.duration(to: .now).formatted(.units(allowed: [.milliseconds])))")
                #endif
            } catch {
                NSLog("markshot: chụp màn hình lỗi: %@", String(describing: error))
                if CGPreflightScreenCaptureAccess() {
                    NSSound.beep()
                } else {
                    showPermissionAlert()
                }
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "markshot cần quyền Screen Recording"
        alert.informativeText = """
            macOS chỉ cho phép chụp nội dung màn hình khi app được cấp quyền Screen Recording.

            Hãy bật markshot trong System Settings → Privacy & Security → Screen Recording, rồi mở lại markshot.
            """
        alert.addButton(withTitle: "Mở System Settings")
        alert.addButton(withTitle: "Để sau")
        // Thông báo phải hiện ở desktop đang dùng, kể cả khi đang ở app full màn hình.
        alert.window.level = .modalPanel
        alert.window.joinAllSpaces()
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Đăng ký markshot vào danh sách Screen Recording (lần đầu macOS sẽ hỏi).
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

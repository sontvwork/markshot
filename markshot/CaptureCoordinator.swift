import AppKit
import os

enum CaptureMode {
    /// Chọn vùng trên overlay phủ tất cả màn hình.
    case region
    /// Màn hình đang có con trỏ, chọn sẵn cả màn hình.
    case screen
    /// Ghép tất cả màn hình thành một ảnh, mở trong cửa sổ riêng.
    case allScreens
}

/// Điểm vào của mọi lần chụp. Mỗi lúc chỉ giữ một phiên chụp.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var session: CaptureSession?
    private var busy = false

    func start(_ mode: CaptureMode) {
        guard session == nil, !busy else { return }
        busy = true
        guard CGPreflightScreenCaptureAccess() else {
            showPermissionAlert()
            busy = false
            return
        }

        // Xác định màn hình cần chụp ngay lúc bấm hotkey, trước khi con trỏ kịp di chuyển.
        let screens = mode == .screen ? [NSScreen.underMouse].compactMap { $0 } : NSScreen.screens
        let started = ContinuousClock.now
        let warm = ScreenCapturer.isWarm
        Task {
            defer { busy = false }
            do {
                let shots = try await ScreenCapturer.capture(screens)
                guard !shots.isEmpty else { return }
                let captured = ContinuousClock.now
                let onEnd = { self.session = nil }
                switch mode {
                case .region:
                    session = CaptureSession(overlay: shots, selectAll: false, onEnd: onEnd)
                case .screen:
                    session = CaptureSession(overlay: shots, selectAll: true, onEnd: onEnd)
                case .allScreens:
                    guard let stitched = ScreenCapturer.stitch(shots) else {
                        NSSound.beep()
                        return
                    }
                    session = CaptureSession(stitched: stitched, onEnd: onEnd)
                }
                #if DEBUG
                let total = Self.milliseconds(started.duration(to: .now))
                let capture = Self.milliseconds(started.duration(to: captured))
                Logger(subsystem: "com.son.markshot", category: "timing").notice(
                    "editor hiện sau \(total, privacy: .public) ms (chụp \(capture, privacy: .public) ms, \(shots.count, privacy: .public) màn hình, danh sách màn hình \(warm ? "có sẵn" : "lấy mới", privacy: .public))"
                )
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

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int((Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15).rounded())
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
        // Thông báo phải hiện được ở mọi desktop, kể cả khi đang ở app full màn hình.
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

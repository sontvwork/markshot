import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.Key.imageFormat) private var format = ImageFormat.png
    @AppStorage(Prefs.Key.jpgQuality) private var jpgQuality = Prefs.defaultJPGQuality
    @AppStorage(Prefs.Key.downscaleRetina) private var downscaleRetina = false
    @AppStorage(Prefs.Key.saveDirectory) private var saveDirectory = Prefs.defaultSaveDirectory
    /// Trạng thái thật nằm ở `SMAppService`; biến này chỉ để công tắc vẽ lại.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Chụp vùng chọn", name: .captureRegion)
                KeyboardShortcuts.Recorder("Chụp toàn màn hình", name: .captureScreen)
                KeyboardShortcuts.Recorder("Chụp nhiều màn hình", name: .captureAllScreens)
            }

            Section("Ảnh") {
                Picker("Format", selection: $format) {
                    ForEach(ImageFormat.allCases, id: \.self) { format in
                        Text(format.title)
                    }
                }
                .pickerStyle(.segmented)

                if format == .jpg {
                    Slider(value: $jpgQuality, in: 0.1...1, step: 0.05) {
                        Text("Chất lượng JPG: \(Int((jpgQuality * 100).rounded()))%")
                    }
                }

                Toggle(isOn: $downscaleRetina) {
                    Text("Downscale Retina")
                    Text("Xuất ảnh ở độ phân giải 1x thay vì độ phân giải gốc của màn hình Retina.")
                }
            }

            Section("Lưu file") {
                LabeledContent("Thư mục lưu mặc định") {
                    Text((saveDirectory as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Chọn…", action: chooseSaveDirectory)
                }
            }

            Section("Hệ thống") {
                Toggle("Tự chạy khi đăng nhập", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsWindowReader())
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: saveDirectory, isDirectory: true)
        panel.prompt = "Chọn"
        let apply: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                saveDirectory = url.path
            }
        }
        // Gắn hộp thoại vào cửa sổ Preferences để nó luôn nằm cùng desktop với cửa sổ đó.
        if let window = SettingsWindow.current {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }
}

/// Đưa cửa sổ Preferences lên trước các app khác, ngay tại màn hình và desktop đang dùng.
///
/// App không có icon Dock nên macOS không tự kích hoạt app khi mở cửa sổ: nếu chỉ gọi `openSettings()`
/// thì cửa sổ mở ra nằm dưới app đang dùng, hoặc nằm lại ở desktop khác.
enum SettingsWindow {
    static weak var current: NSWindow?

    static func bringToFront() {
        // Chờ sang lượt chạy kế tiếp: menu đã đóng hẳn và SwiftUI đã tạo xong cửa sổ.
        Task {
            guard let window = current else { return }
            // Nổi trên các cửa sổ thường và có mặt ở mọi desktop: không phụ thuộc việc macOS có chịu
            // kích hoạt app hay không, và hiện được cả trong space của app full màn hình.
            window.level = .floating
            window.joinAllSpaces()

            // Mở ở màn hình đang có con trỏ (nơi vừa bấm menu), không phải màn hình lần trước.
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), window.screen != screen {
                let visible = screen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: (visible.midX - window.frame.width / 2).rounded(),
                    y: (visible.midY - window.frame.height / 2).rounded()
                ))
            }

            window.orderFrontRegardless()
            window.makeKey()
            // Kích hoạt sau khi cửa sổ đã nằm ở desktop này, để macOS không có lý do chuyển desktop.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// View ẩn nằm trong Preferences, dùng để lấy được `NSWindow` mà SwiftUI tạo ra.
private struct SettingsWindowReader: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SettingsWindow.current = window
            SettingsWindow.bringToFront()
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

import AppKit
import ScreenCaptureKit

/// Ảnh chụp của một màn hình.
struct ScreenShot {
    let screen: NSScreen
    let image: CGImage

    /// Số pixel ảnh trên mỗi point của màn hình.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

enum ScreenCapturer {
    /// Chụp các màn hình cùng lúc, ở độ phân giải gốc, không kèm con trỏ chuột.
    static func capture(_ screens: [NSScreen]) async throws -> [ScreenShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Loại cửa sổ của chính markshot (menu đang đóng, Preferences) khỏi ảnh.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }

        let tasks = screens.compactMap { screen -> Task<ScreenShot, Error>? in
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
            config.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            return Task {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                return ScreenShot(screen: screen, image: image)
            }
        }

        var shots: [ScreenShot] = []
        for task in tasks {
            shots.append(try await task.value)
        }
        return shots
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

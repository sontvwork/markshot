import AppKit
import ScreenCaptureKit

/// Ảnh chụp của một màn hình.
struct ScreenShot {
    let screen: NSScreen
    let image: CGImage

    /// Số pixel ảnh trên mỗi point của màn hình.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

/// Ảnh ghép của nhiều màn hình.
struct StitchedShot {
    let image: CGImage
    /// Kích thước theo point: khung bao của tất cả màn hình.
    let canvasSize: CGSize
    /// Số pixel ảnh trên mỗi point.
    let scale: CGFloat
}

enum ScreenCapturer {
    private enum CaptureError: Error {
        case displayNotFound
    }

    /// Danh sách màn hình lấy từ ScreenCaptureKit. Giữ lại giữa các lần chụp vì lấy nó chậm,
    /// nhất là lần đầu sau khi mở app. Bỏ đi khi cấu hình màn hình thay đổi.
    private static var cachedDisplays: [SCDisplay]?

    /// Đã có sẵn danh sách màn hình cho lần chụp tới hay chưa (để ghi log thời gian).
    static var isWarm: Bool { cachedDisplays != nil }

    /// Lấy sẵn danh sách màn hình để lần chụp đầu tiên không phải chờ ScreenCaptureKit khởi động.
    static func warmUp() {
        // Chưa có quyền thì không gọi, kẻo macOS bật hộp thoại xin quyền ngay lúc mở app.
        guard CGPreflightScreenCaptureAccess() else { return }
        Task {
            _ = try? await displays()
        }
    }

    static func invalidate() {
        cachedDisplays = nil
    }

    private static func displays() async throws -> [SCDisplay] {
        if let cachedDisplays { return cachedDisplays }
        let displays = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
        cachedDisplays = displays
        return displays
    }

    /// Chụp các màn hình cùng lúc, ở độ phân giải gốc, không kèm con trỏ chuột.
    static func capture(_ screens: [NSScreen]) async throws -> [ScreenShot] {
        let usedCache = cachedDisplays != nil
        do {
            return try await capture(screens, displays: try await displays())
        } catch where usedCache {
            // Danh sách đã lưu có thể cũ (vừa cắm màn hình, máy vừa thức dậy): lấy lại rồi thử thêm một lần.
            cachedDisplays = nil
            return try await capture(screens, displays: try await displays())
        }
    }

    private static func capture(_ screens: [NSScreen], displays: [SCDisplay]) async throws -> [ScreenShot] {
        let tasks = try screens.map { screen -> Task<ScreenShot, Error> in
            guard let display = displays.first(where: { $0.displayID == screen.displayID }) else {
                throw CaptureError.displayNotFound
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
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

    /// Ghép các màn hình thành một ảnh, xếp đúng vị trí tương đối như trong System Settings → Displays.
    /// Mọi màn hình được đưa về cùng tỉ lệ (tỉ lệ lớn nhất); chỗ trống giữa các màn hình để trong suốt.
    static func stitch(_ shots: [ScreenShot]) -> StitchedShot? {
        stitch(shots.map { ($0.image, $0.screen.frame) })
    }

    /// `frame` của từng ảnh theo toạ độ màn hình của AppKit (point, trục y hướng lên).
    static func stitch(_ parts: [(image: CGImage, frame: CGRect)]) -> StitchedShot? {
        guard let first = parts.first else { return nil }
        let union = parts.reduce(first.frame) { $0.union($1.frame) }
        let scales = parts.map { CGFloat($0.image.width) / $0.frame.width }
        let scale = scales.max() ?? 1
        let width = Int((union.width * scale).rounded())
        let height = Int((union.height * scale).rounded())
        guard let ctx = CGContext.bitmap(width: width, height: height, matching: first.image, opaque: false) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        for (part, partScale) in zip(parts, scales) {
            // Phóng theo bội số nguyên (màn hình 1x vào ảnh 2x) thì nhân đôi pixel cho nét, không làm nhoè.
            let ratio = scale / partScale
            ctx.interpolationQuality = ratio == ratio.rounded() ? .none : .high
            // Toạ độ màn hình của AppKit và bitmap của Core Graphics đều có trục y hướng lên.
            ctx.draw(part.image, in: part.frame.offsetBy(dx: -union.minX, dy: -union.minY))
        }
        guard let image = ctx.makeImage() else { return nil }
        return StitchedShot(image: image, canvasSize: union.size, scale: scale)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Màn hình đang có con trỏ chuột.
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main ?? screens.first
    }
}

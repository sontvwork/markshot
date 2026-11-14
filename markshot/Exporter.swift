import AppKit

enum Exporter {
    /// Ảnh xuất ra: vùng chọn (toạ độ point của canvas) cắt từ ảnh gốc, đã gộp nét vẽ.
    ///
    /// - Parameters:
    ///   - pixelScale: số pixel ảnh gốc trên mỗi point canvas.
    ///   - outputScale: số pixel ảnh xuất ra trên mỗi point canvas (1 khi bật Downscale Retina).
    static func render(
        image: CGImage,
        pixelScale: CGFloat,
        outputScale: CGFloat,
        selection: CGRect,
        annotations: [Annotation],
        pixelated: (Annotation) -> CGImage?
    ) -> CGImage? {
        let sourceRect = CGRect(
            x: (selection.minX * pixelScale).rounded(),
            y: (selection.minY * pixelScale).rounded(),
            width: (selection.width * pixelScale).rounded(),
            height: (selection.height * pixelScale).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !sourceRect.isEmpty, let cropped = image.cropping(to: sourceRect) else { return nil }
        // Không nét vẽ, không đổi tỉ lệ: dùng thẳng phần cắt từ ảnh gốc, không phải vẽ lại.
        if annotations.isEmpty, outputScale == pixelScale {
            return cropped
        }

        let width = max(1, Int((selection.width * outputScale).rounded()))
        let height = max(1, Int((selection.height * outputScale).rounded()))
        guard let ctx = CGContext.bitmap(width: width, height: height, matching: image, opaque: image.isOpaque) else { return nil }

        // Đưa context về toạ độ canvas: gốc trên-trái, đơn vị point.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: outputScale, y: -outputScale)
        ctx.translateBy(x: -selection.minX, y: -selection.minY)

        ctx.interpolationQuality = outputScale == pixelScale ? .none : .high
        ctx.drawUpright(cropped, in: selection)
        ctx.interpolationQuality = .default

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ctx.clip(to: selection)
        for annotation in annotations {
            annotation.draw(in: ctx, pixelated: pixelated)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// `pointSize` ghi vào metadata (DPI) để ảnh Retina hiện đúng kích thước ở các app tôn trọng DPI.
    private static func bitmap(_ image: CGImage, pointSize: CGSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(cgImage: image)
        if pointSize.width > 0, pointSize.height > 0 {
            rep.size = pointSize
        }
        return rep
    }

    /// Đưa ảnh vào clipboard.
    static func copy(_ image: CGImage, pointSize: CGSize) {
        autoreleasepool {
            let rep = bitmap(image, pointSize: pointSize)
            let item = NSPasteboardItem()
            if let png = rep.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
            let lzw = NSBitmapImageRep.TIFFCompression.lzw.rawValue
            if let tiff = rep.representation(using: .tiff, properties: [.compressionMethod: lzw]) {
                item.setData(tiff, forType: .tiff)
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
        }
    }

    /// Hỏi nơi lưu bằng hộp thoại của hệ thống rồi ghi file theo format trong Preferences.
    ///
    /// Hộp thoại được gắn vào `window` dưới dạng sheet. Không dùng `runModal()`: khi chạy modal, AppKit ép
    /// hộp thoại về mức `modalPanel`, thấp hơn overlay, nên nó bị overlay che mất trong khi app đứng chờ nó.
    ///
    /// - Parameter completion: `true` khi đã lưu xong; `false` nếu bấm Cancel hoặc ghi lỗi (editor vẫn mở).
    static func save(_ image: CGImage, pointSize: CGSize, on window: NSWindow, completion: @escaping (Bool) -> Void) {
        let format = Prefs.imageFormat
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let panel = NSSavePanel()
        panel.directoryURL = Prefs.saveDirectory
        panel.nameFieldStringValue = "markshot_\(formatter.string(from: Date())).\(format.rawValue)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        // Kích hoạt app để gõ được tên file ngay.
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            do {
                try write(image, pointSize: pointSize, to: url, format: format)
                completion(true)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window) { _ in
                    completion(false)
                }
            }
        }
    }

    /// Ghi ảnh ra file theo format đã chọn. JPG dùng chất lượng trong Preferences.
    static func write(_ image: CGImage, pointSize: CGSize, to url: URL, format: ImageFormat) throws {
        try autoreleasepool {
            let rep = bitmap(image, pointSize: pointSize)
            // JPG không có kênh alpha: vùng trong suốt được NSBitmapImageRep tô trắng.
            let data = format == .png
                ? rep.representation(using: .png, properties: [:])
                : rep.representation(using: .jpeg, properties: [.compressionFactor: Prefs.jpgQuality])
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
    }
}

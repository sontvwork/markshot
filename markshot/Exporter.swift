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
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        guard let ctx = CGContext.bitmap(width: width, height: height, matching: image, opaque: opaque) else { return nil }

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
    /// Trả về `false` nếu người dùng bấm Cancel hoặc ghi lỗi (khi đó editor vẫn mở).
    static func save(_ image: CGImage, pointSize: CGSize, above level: NSWindow.Level) -> Bool {
        let format = Prefs.imageFormat
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let panel = NSSavePanel()
        panel.directoryURL = Prefs.saveDirectory
        panel.nameFieldStringValue = "markshot_\(formatter.string(from: Date())).\(format.rawValue)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        // Hộp thoại phải nổi trên overlay và hiện được ở mọi desktop, kể cả space full màn hình.
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.modalPanel.rawValue, level.rawValue + 1))
        panel.joinAllSpaces()
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try autoreleasepool {
                let rep = bitmap(image, pointSize: pointSize)
                // JPG không có kênh alpha: vùng trong suốt được NSBitmapImageRep tô trắng.
                let data = format == .png
                    ? rep.representation(using: .png, properties: [:])
                    : rep.representation(using: .jpeg, properties: [.compressionFactor: Prefs.jpgQuality])
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            }
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.window.level = panel.level
            alert.window.joinAllSpaces()
            alert.runModal()
            return false
        }
    }
}

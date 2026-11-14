import AppKit

enum Exporter {
    /// Ảnh xuất ra: vùng chọn (toạ độ point của canvas) cắt từ ảnh gốc, đã gộp nét vẽ.
    static func render(
        image: CGImage,
        pixelScale: CGFloat,
        selection: CGRect,
        annotations: [Annotation],
        pixelated: (Annotation) -> CGImage?
    ) -> CGImage? {
        let pixelRect = CGRect(
            x: (selection.minX * pixelScale).rounded(),
            y: (selection.minY * pixelScale).rounded(),
            width: (selection.width * pixelScale).rounded(),
            height: (selection.height * pixelScale).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixelRect.isEmpty else { return nil }
        // Không có nét vẽ: cắt thẳng từ ảnh gốc, không phải vẽ lại.
        if annotations.isEmpty {
            return image.cropping(to: pixelRect)
        }

        let width = Int(pixelRect.width), height = Int(pixelRect.height)
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        guard let ctx = CGContext.bitmap(width: width, height: height, matching: image, opaque: opaque) else { return nil }

        // Đưa context về toạ độ canvas: gốc trên-trái, đơn vị point.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: pixelScale, y: -pixelScale)
        ctx.translateBy(x: -pixelRect.minX / pixelScale, y: -pixelRect.minY / pixelScale)

        ctx.interpolationQuality = .none
        ctx.drawUpright(image, in: CGRect(
            x: 0, y: 0, width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale
        ))
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

    /// Đưa ảnh vào clipboard. `pointSize` ghi vào metadata để ảnh Retina dán ra đúng kích thước.
    static func copy(_ image: CGImage, pointSize: CGSize) {
        autoreleasepool {
            let rep = NSBitmapImageRep(cgImage: image)
            if pointSize.width > 0, pointSize.height > 0 {
                rep.size = pointSize
            }
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
}

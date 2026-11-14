import AppKit

enum Exporter {
    /// Cắt vùng chọn (toạ độ point của canvas) ra khỏi ảnh gốc.
    static func render(image: CGImage, pixelScale: CGFloat, selection: CGRect) -> CGImage? {
        let pixelRect = CGRect(
            x: (selection.minX * pixelScale).rounded(),
            y: (selection.minY * pixelScale).rounded(),
            width: (selection.width * pixelScale).rounded(),
            height: (selection.height * pixelScale).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixelRect.isEmpty else { return nil }
        return image.cropping(to: pixelRect)
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

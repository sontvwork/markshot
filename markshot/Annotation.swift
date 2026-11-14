import AppKit

enum Tool: CaseIterable {
    case pen, line, arrow, rectangle, marker, text, pixelate, counter

    var symbol: String {
        switch self {
        case .pen: "pencil"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .marker: "highlighter"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .counter: "1.circle"
        }
    }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .marker: "Marker"
        case .text: "Text"
        case .pixelate: "Pixelate"
        case .counter: "Đánh số bước"
        }
    }
}

enum StrokeSize: Int {
    case small, medium, large

    var lineWidth: CGFloat {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 7
        }
    }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    var next: StrokeSize { StrokeSize(rawValue: rawValue + 1) ?? .small }
}

/// Một nét vẽ trên canvas. Toạ độ theo point của canvas, gốc trên-trái.
struct Annotation {
    enum Shape {
        case stroke(points: [CGPoint], marker: Bool)
        case line(from: CGPoint, to: CGPoint, arrow: Bool)
        case rectangle(CGRect)
        case pixelate(CGRect)
        case counter(center: CGPoint, number: Int, radius: CGFloat)
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
    }

    let id: Int
    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat

    static let defaultFontSize: CGFloat = 20
    private static let markerScale: CGFloat = 4
    private static let markerAlpha: CGFloat = 0.4

    /// Bán kính hình tròn đánh số theo mức S/M/L.
    static func counterRadius(for size: StrokeSize) -> CGFloat { 6 + size.lineWidth * 2 }

    /// Bề rộng nét thực tế: Marker to gấp nhiều lần nét thường.
    var strokeWidth: CGFloat {
        if case .stroke(_, true) = shape { return lineWidth * Self.markerScale }
        return lineWidth
    }

    // MARK: Text

    static func textFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    private static func attributedText(_ string: String, fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: textFont(size: fontSize), .foregroundColor: color])
    }

    static func textSize(_ string: String, fontSize: CGFloat) -> CGSize {
        let rect = attributedText(string, fontSize: fontSize, color: .black).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// Khung bao của text; `nil` nếu không phải text.
    var textFrame: CGRect? {
        guard case .text(let origin, let string, let fontSize) = shape else { return nil }
        return CGRect(origin: origin, size: Self.textSize(string, fontSize: fontSize))
    }

    // MARK: Hình học

    /// Vùng cần vẽ lại khi nét vẽ này thay đổi.
    var bounds: CGRect {
        switch shape {
        case .stroke(let points, _):
            return Self.boundingBox(points).insetBy(dx: -strokeWidth, dy: -strokeWidth)
        case .line(let from, let to, _):
            let margin = lineWidth * 2 + 8
            return Self.boundingBox([from, to]).insetBy(dx: -margin, dy: -margin)
        case .rectangle(let rect):
            return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .pixelate(let rect):
            return rect
        case .counter(let center, _, let counterRadius):
            let radius = counterRadius + 1
            return CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        case .text:
            return textFrame ?? .zero
        }
    }

    /// Nét vẽ quá nhỏ (click mà không kéo) thì bỏ.
    var isMeaningful: Bool {
        switch shape {
        case .line(let from, let to, _): hypot(to.x - from.x, to.y - from.y) >= 3
        case .rectangle(let rect), .pixelate(let rect): rect.width >= 3 && rect.height >= 3
        default: true
        }
    }

    static func boundingBox<Points: Collection>(_ points: Points) -> CGRect where Points.Element == CGPoint {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Vẽ

    /// Vẽ vào context có trục y hướng xuống và đang là `NSGraphicsContext.current` (để vẽ được chữ).
    /// Dùng chung cho màn hình và ảnh xuất ra.
    func draw(in ctx: CGContext, pixelated: (Annotation) -> CGImage?) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch shape {
        case .stroke(let points, let marker):
            guard let first = points.first, let last = points.last else { return }
            let width = strokeWidth
            ctx.setLineWidth(width)
            if marker {
                ctx.setAlpha(Self.markerAlpha)
            }
            if points.count == 1 {
                ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
                return
            }
            // Làm mượt bằng đường cong đi qua trung điểm của từng đoạn.
            ctx.move(to: first)
            for index in 1..<(points.count - 1) {
                let current = points[index], next = points[index + 1]
                ctx.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
            }
            ctx.addLine(to: last)
            ctx.strokePath()

        case .line(let from, let to, let arrow):
            let length = hypot(to.x - from.x, to.y - from.y)
            guard arrow, length > 0 else {
                ctx.move(to: from)
                ctx.addLine(to: to)
                ctx.strokePath()
                return
            }
            let head = min(max(lineWidth * 4, 12), length)
            let ux = (to.x - from.x) / length, uy = (to.y - from.y) / length
            let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
            let half = head * 0.45
            ctx.move(to: from)
            ctx.addLine(to: base)
            ctx.strokePath()
            ctx.move(to: to)
            ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            ctx.closePath()
            ctx.fillPath()

        case .rectangle(let rect):
            ctx.setLineJoin(.miter)
            ctx.stroke(rect)

        case .pixelate(let rect):
            guard let image = pixelated(self) else { return }
            ctx.interpolationQuality = .none
            ctx.drawUpright(image, in: rect)

        case .counter(let center, let number, let radius):
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: radius * 1.15, weight: .bold),
                .foregroundColor: color.contrastingTextColor,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        case .text(let origin, let string, let fontSize):
            Self.attributedText(string, fontSize: fontSize, color: color).draw(
                with: CGRect(origin: origin, size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)),
                options: [.usesLineFragmentOrigin]
            )
        }
    }
}

enum Pixelator {
    /// Cạnh của mỗi ô vỡ hạt, tính theo point.
    private static let block: CGFloat = 10

    /// Ảnh thu nhỏ của vùng `rect` (point canvas); vẽ phóng lại không nội suy sẽ ra hiệu ứng vỡ hạt.
    static func image(of rect: CGRect, in base: CGImage, pixelScale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(
            x: rect.minX * pixelScale, y: rect.minY * pixelScale,
            width: rect.width * pixelScale, height: rect.height * pixelScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !pixelRect.isEmpty, let cropped = base.cropping(to: pixelRect) else { return nil }

        let width = max(1, Int((rect.width / block).rounded(.up)))
        let height = max(1, Int((rect.height / block).rounded(.up)))
        // Giữ kênh alpha của ảnh gốc: vùng trống trong suốt của ảnh ghép không được biến thành đen.
        guard let ctx = CGContext.bitmap(width: width, height: height, matching: base, opaque: base.isOpaque) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

extension CGImage {
    /// Ảnh không có kênh alpha (ảnh chụp một màn hình). Ảnh ghép nhiều màn hình thì có vùng trong suốt.
    var isOpaque: Bool {
        [.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }
}

extension CGContext {
    /// Bitmap BGRA cùng không gian màu với `image` (rơi về sRGB nếu không gian màu đó không vẽ được).
    static func bitmap(width: Int, height: Int, matching image: CGImage, opaque: Bool) -> CGContext? {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipFirst : .premultipliedFirst
        let bitmapInfo = alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        for space in [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)] {
            guard let space else { continue }
            if let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: bitmapInfo
            ) {
                return ctx
            }
        }
        return nil
    }

    /// Vẽ ảnh đúng chiều trong context có trục y hướng xuống.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    var rgb: Int? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
    }

    /// Màu chữ dễ đọc khi đặt trên nền màu này.
    var contrastingTextColor: NSColor {
        guard let color = usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return luminance > 0.65 ? .black : .white
    }
}

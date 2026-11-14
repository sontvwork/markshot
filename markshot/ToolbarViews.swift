import AppKit

/// Thanh nổi nền tối chứa một hàng (hoặc một cột) nút biểu tượng.
final class BarView: NSView {
    private static let buttonSize: CGFloat = 30
    private static let padding: CGFloat = 4
    private static let spacing: CGFloat = 2

    private let vertical: Bool

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = 8
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }

    /// Click vào nền thanh không được lọt xuống canvas.
    override func mouseDown(with event: NSEvent) {}

    @discardableResult
    func addButton(symbol: String, tooltip: String, action: @escaping () -> Void) -> BarButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        return addButton(image: image, tooltip: tooltip, action: action)
    }

    @discardableResult
    func addButton(image: NSImage?, tooltip: String, action: @escaping () -> Void) -> BarButton {
        let button = BarButton(image: image, tooltip: tooltip, handler: action)
        let offset = Self.padding + CGFloat(subviews.count) * (Self.buttonSize + Self.spacing)
        button.frame = CGRect(
            x: vertical ? Self.padding : offset,
            y: vertical ? offset : Self.padding,
            width: Self.buttonSize,
            height: Self.buttonSize
        )
        addSubview(button)

        let length = offset + Self.buttonSize + Self.padding
        let thickness = Self.buttonSize + 2 * Self.padding
        setFrameSize(vertical ? NSSize(width: thickness, height: length) : NSSize(width: length, height: thickness))
        return button
    }
}

final class BarButton: NSButton {
    private let handler: () -> Void

    /// Công cụ đang được chọn thì có nền sáng.
    var isSelected = false {
        didSet { layer?.backgroundColor = isSelected ? NSColor(white: 1, alpha: 0.28).cgColor : nil }
    }

    init(image: NSImage?, tooltip: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .white
        toolTip = tooltip
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = 6
        target = self
        action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    @objc private func fire() {
        handler()
    }
}

extension NSImage {
    private static let iconSize = NSSize(width: 16, height: 16)

    /// Chấm tròn mang màu vẽ hiện tại, dùng cho nút chọn màu.
    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: iconSize, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            color.setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
    }

    /// Chấm trắng to nhỏ theo độ dày nét, dùng cho nút S/M/L.
    static func strokeDot(_ size: StrokeSize) -> NSImage {
        let diameter = 4 + CGFloat(size.rawValue) * 4.5
        return NSImage(size: iconSize, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter
            )).fill()
            return true
        }
    }
}

enum BarLayout {
    /// Tính vị trí hai thanh quanh vùng chọn, trong toạ độ view lật (gốc trên-trái).
    ///
    /// Thanh công cụ (dọc): bên phải → bên trái → vào trong. Thanh hành động (ngang): bên dưới → bên trên → vào trong.
    static func place(
        selection s: CGRect,
        bounds b: CGRect,
        toolSize: CGSize?,
        actionSize: CGSize,
        gap: CGFloat = 8
    ) -> (tool: CGRect?, action: CGRect) {
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            max(low, min(value, high))
        }

        var tool: CGRect?
        if let size = toolSize {
            var x = s.maxX + gap
            if x + size.width > b.maxX { x = s.minX - gap - size.width }
            if x < b.minX { x = s.maxX - gap - size.width }
            tool = CGRect(
                x: clamp(x, b.minX + gap, b.maxX - gap - size.width),
                y: clamp(s.minY, b.minY + gap, b.maxY - gap - size.height),
                width: size.width,
                height: size.height
            )
        }

        var x = s.maxX - actionSize.width
        var y = s.maxY + gap
        if y + actionSize.height > b.maxY { y = s.minY - gap - actionSize.height }
        if y < b.minY {
            y = s.maxY - gap - actionSize.height
            x -= gap
        }
        var action = CGRect(
            x: clamp(x, b.minX + gap, b.maxX - gap - actionSize.width),
            y: clamp(y, b.minY + gap, b.maxY - gap - actionSize.height),
            width: actionSize.width,
            height: actionSize.height
        )
        // Hai thanh đè nhau (cùng nằm trong vùng chọn, hoặc bị dồn vào mép màn hình): tách ra.
        if var moved = tool, action.intersects(moved) {
            let actionLeft = moved.minX - gap - actionSize.width
            let toolRight = action.maxX + gap
            if actionLeft >= b.minX + gap {
                action.origin.x = actionLeft
            } else if toolRight + moved.width <= b.maxX - gap {
                moved.origin.x = toolRight
                tool = moved
            } else {
                let below = moved.maxY + gap
                action.origin.y = below + actionSize.height <= b.maxY ? below : moved.minY - gap - actionSize.height
            }
        }
        return (tool, action)
    }
}

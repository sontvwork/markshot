import AppKit

/// Canvas của editor: hiện ảnh đã chụp, lớp tối, vùng chọn và hai thanh công cụ.
/// Dùng chung cho overlay (tỉ lệ 1:1) và cửa sổ ảnh ghép (ảnh thu nhỏ cho vừa cửa sổ).
///
/// Vùng chọn lưu theo point của canvas, gốc trên-trái. Mọi thứ hiển thị đều là view dùng layer
/// (không có `draw(_:)`), nên kéo vùng chọn chỉ là đổi frame, không phải vẽ lại.
final class EditorView: NSView {
    // MARK: Cấu hình

    let image: CGImage
    /// Số pixel ảnh trên mỗi point canvas.
    let pixelScale: CGFloat
    let canvasSize: CGSize
    private let inset: CGFloat

    // MARK: Callback về phiên chụp

    var shouldBeginSelection: () -> Bool = { true }
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onClose: () -> Void = {}

    // MARK: Trạng thái

    private(set) var selection: CGRect? {
        didSet { layoutChrome() }
    }

    /// Chỉ được chọn lại vùng từ đầu khi chưa có nét vẽ nào.
    var canReselect: Bool { true }

    private enum Drag {
        case creating(anchor: CGPoint)
        case moving(grab: CGPoint, start: CGRect)
        case resizing(Handle, start: CGRect)
    }

    private var drag: Drag?

    /// Khung của canvas trong view, và tỉ lệ point view / point canvas.
    private var canvasFrame = CGRect.zero
    private var zoom: CGFloat = 1

    // MARK: View con

    private let imageView = NSView()
    private let dimViews = (0..<4).map { _ in NSView() }
    private let borderOuter = NSView()
    private let borderInner = NSView()
    private let handleViews = Handle.all.map { _ in NSView() }
    private let sizeBox = NSView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let actionBar = BarView(vertical: false)

    init(image: CGImage, pixelScale: CGFloat, canvasSize: CGSize, inset: CGFloat = 0) {
        self.image = image
        self.pixelScale = pixelScale
        self.canvasSize = canvasSize
        self.inset = inset
        super.init(frame: CGRect(x: 0, y: 0, width: canvasSize.width + 2 * inset, height: canvasSize.height + 2 * inset))
        wantsLayer = true

        imageView.wantsLayer = true
        imageView.layerContentsRedrawPolicy = .never
        imageView.layer?.contents = image
        imageView.layer?.contentsGravity = .resize
        addSubview(imageView)

        for view in dimViews {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
            addSubview(view)
        }

        for (view, color) in [(borderOuter, NSColor(white: 0, alpha: 0.5)), (borderInner, NSColor.white)] {
            view.wantsLayer = true
            view.layer?.borderWidth = 1
            view.layer?.borderColor = color.cgColor
            addSubview(view)
        }

        for view in handleViews {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.white.cgColor
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor(white: 0, alpha: 0.6).cgColor
            view.layer?.cornerRadius = Handle.size / 2
            addSubview(view)
        }

        sizeBox.wantsLayer = true
        sizeBox.layer?.backgroundColor = NSColor(white: 0, alpha: 0.7).cgColor
        sizeBox.layer?.cornerRadius = 4
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white
        sizeBox.addSubview(sizeLabel)
        addSubview(sizeBox)

        // M3 mới có Save.
        actionBar.addButton(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)") { [weak self] in self?.onSave() }
            .isEnabled = false
        actionBar.addButton(symbol: "doc.on.doc", tooltip: "Copy (⌘C)") { [weak self] in self?.onCopy() }
        actionBar.addButton(symbol: "xmark", tooltip: "Đóng (Esc)") { [weak self] in self?.onClose() }
        addSubview(actionBar)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        updateGeometry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func clearSelection() {
        drag = nil
        selection = nil
    }

    /// Ảnh xuất ra: vùng chọn cắt từ ảnh gốc.
    func renderSelection() -> CGImage? {
        guard let selection else { return nil }
        return Exporter.render(image: image, pixelScale: pixelScale, selection: selection)
    }

    // MARK: Bố cục

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func updateGeometry() {
        let available = bounds.insetBy(dx: inset, dy: inset)
        guard available.width > 0, available.height > 0 else { return }
        zoom = min(available.width / canvasSize.width, available.height / canvasSize.height, 1)
        let size = CGSize(width: canvasSize.width * zoom, height: canvasSize.height * zoom)
        canvasFrame = CGRect(
            x: (available.midX - size.width / 2).rounded(),
            y: (available.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        imageView.frame = canvasFrame
        layoutChrome()
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: canvasFrame.minX + rect.minX * zoom,
            y: canvasFrame.minY + rect.minY * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    /// Đặt lại lớp tối, viền, tay nắm, nhãn kích thước và thanh hành động theo vùng chọn hiện tại.
    private func layoutChrome() {
        var creating = false
        if case .creating = drag { creating = true }

        guard let selection else {
            dimViews[0].frame = canvasFrame
            dimViews[1...].forEach { $0.frame = .zero }
            ([borderOuter, borderInner, sizeBox, actionBar] + handleViews).forEach { $0.isHidden = true }
            return
        }

        let r = viewRect(selection)
        let c = canvasFrame
        dimViews[0].frame = CGRect(x: c.minX, y: c.minY, width: c.width, height: r.minY - c.minY)
        dimViews[1].frame = CGRect(x: c.minX, y: r.maxY, width: c.width, height: c.maxY - r.maxY)
        dimViews[2].frame = CGRect(x: c.minX, y: r.minY, width: r.minX - c.minX, height: r.height)
        dimViews[3].frame = CGRect(x: r.maxX, y: r.minY, width: c.maxX - r.maxX, height: r.height)

        borderInner.frame = r.insetBy(dx: -1, dy: -1)
        borderOuter.frame = r.insetBy(dx: -2, dy: -2)
        borderInner.isHidden = false
        borderOuter.isHidden = false

        for (handle, view) in zip(Handle.all, handleViews) {
            let p = handle.point(in: r)
            view.frame = CGRect(x: p.x - Handle.size / 2, y: p.y - Handle.size / 2, width: Handle.size, height: Handle.size)
            view.isHidden = creating
        }

        let width = Int((selection.width * pixelScale).rounded())
        let height = Int((selection.height * pixelScale).rounded())
        sizeLabel.stringValue = "\(width) × \(height)"
        sizeLabel.sizeToFit()
        sizeLabel.setFrameOrigin(CGPoint(x: 6, y: 3))
        let boxSize = CGSize(width: sizeLabel.frame.width + 12, height: sizeLabel.frame.height + 6)
        var boxOrigin = CGPoint(x: r.minX, y: r.minY - boxSize.height - 6)
        if boxOrigin.y < bounds.minY + 2 {
            // Không còn chỗ phía trên: đưa nhãn vào trong vùng chọn.
            boxOrigin = CGPoint(x: r.minX + 6, y: r.minY + 6)
        }
        boxOrigin.x = max(min(boxOrigin.x, bounds.maxX - boxSize.width - 2), bounds.minX + 2)
        sizeBox.frame = CGRect(origin: boxOrigin, size: boxSize)
        sizeBox.isHidden = false

        actionBar.isHidden = creating
        if !creating {
            let placed = BarLayout.place(selection: r, bounds: bounds, toolSize: nil, actionSize: actionBar.frame.size)
            actionBar.setFrameOrigin(placed.action.origin)
        }
    }

    // MARK: Chuột

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(p) else { return nil }
        if !actionBar.isHidden, actionBar.frame.contains(p) {
            return super.hitTest(point)
        }
        return self
    }

    private func viewPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// Đổi điểm trong view sang toạ độ canvas, giữ trong phạm vi canvas.
    private func canvasPoint(_ v: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max((v.x - canvasFrame.minX) / zoom, 0), canvasSize.width),
            y: min(max((v.y - canvasFrame.minY) / zoom, 0), canvasSize.height)
        )
    }

    private func handle(at v: CGPoint) -> Handle? {
        guard let selection else { return nil }
        let r = viewRect(selection)
        return Handle.all.first { handle in
            let p = handle.point(in: r)
            return abs(p.x - v.x) <= Handle.hitRadius && abs(p.y - v.y) <= Handle.hitRadius
        }
    }

    /// Làm tròn các cạnh theo lưới pixel của ảnh để ảnh xuất ra không lệch pixel.
    private func snapped(_ rect: CGRect) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value * pixelScale).rounded() / pixelScale }
        let x0 = snap(rect.minX), y0 = snap(rect.minY)
        return CGRect(x: x0, y: y0, width: snap(rect.maxX) - x0, height: snap(rect.maxY) - y0)
    }

    override func mouseDown(with event: NSEvent) {
        let v = viewPoint(event)
        let p = canvasPoint(v)
        if let selection {
            if let handle = handle(at: v) {
                drag = .resizing(handle, start: selection)
                return
            }
            if viewRect(selection).contains(v) {
                drag = .moving(grab: p, start: selection)
                NSCursor.closedHand.set()
                return
            }
            guard canReselect else { return }
        }
        guard canvasFrame.contains(v), shouldBeginSelection() else { return }
        drag = .creating(anchor: p)
        selection = nil
        NSCursor.crosshair.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = canvasPoint(viewPoint(event))
        switch drag {
        case .creating(let anchor):
            let rect = snapped(CGRect(
                x: min(anchor.x, p.x), y: min(anchor.y, p.y),
                width: abs(p.x - anchor.x), height: abs(p.y - anchor.y)
            ))
            selection = rect.isEmpty ? nil : rect

        case .moving(let grab, let start):
            var rect = start.offsetBy(dx: p.x - grab.x, dy: p.y - grab.y)
            rect.origin.x = min(max(rect.minX, 0), canvasSize.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), canvasSize.height - rect.height)
            selection = snapped(rect)

        case .resizing(let handle, let start):
            var x0 = start.minX, x1 = start.maxX, y0 = start.minY, y1 = start.maxY
            if handle.x < 0 { x0 = p.x } else if handle.x > 0 { x1 = p.x }
            if handle.y < 0 { y0 = p.y } else if handle.y > 0 { y1 = p.y }
            let rect = snapped(CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0)))
            if !rect.isEmpty { selection = rect }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let finished = drag else { return }
        drag = nil
        // Click hoặc kéo quá ngắn thì coi như chưa chọn.
        if case .creating = finished, let selection, selection.width < 3 || selection.height < 3 {
            self.selection = nil
        } else {
            layoutChrome()
        }
        updateCursor(at: viewPoint(event))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: viewPoint(event))
    }

    private func updateCursor(at v: CGPoint) {
        guard drag == nil else { return }
        let cursor: NSCursor
        if !actionBar.isHidden, actionBar.frame.contains(v) {
            cursor = .arrow
        } else if let selection {
            if let handle = handle(at: v) {
                cursor = handle.cursor
            } else if viewRect(selection).contains(v) {
                cursor = .openHand
            } else {
                cursor = canReselect ? .crosshair : .arrow
            }
        } else {
            cursor = .crosshair
        }
        cursor.set()
    }

    // MARK: Bàn phím

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onClose()
        }
        // Nuốt các phím khác để không kêu "beep".
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if modifiers == .command, drag == nil, selection != nil {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": onCopy()
            case "s": onSave()
            default: break
            }
        }
        // Không để phím tắt ⌘ rơi xuống main menu (⌘H, ⌘Q…) khi overlay đang mở.
        return true
    }
}

/// Một trong 8 tay nắm resize của vùng chọn.
private struct Handle {
    /// -1: cạnh trái/trên, 0: giữa, 1: cạnh phải/dưới.
    let x: Int
    let y: Int

    static let size: CGFloat = 9
    static let hitRadius: CGFloat = 7
    /// Góc trước, cạnh sau: vùng chọn nhỏ thì ưu tiên bắt tay nắm góc.
    static let all = [(-1, -1), (1, -1), (-1, 1), (1, 1), (0, -1), (-1, 0), (1, 0), (0, 1)].map { Handle(x: $0.0, y: $0.1) }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: x < 0 ? rect.minX : x > 0 ? rect.maxX : rect.midX,
            y: y < 0 ? rect.minY : y > 0 ? rect.maxY : rect.midY
        )
    }

    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition
        switch (x, y) {
        case (-1, -1): position = .topLeft
        case (1, -1): position = .topRight
        case (-1, 1): position = .bottomLeft
        case (1, 1): position = .bottomRight
        case (0, -1): position = .top
        case (-1, 0): position = .left
        case (1, 0): position = .right
        default: position = .bottom
        }
        return .frameResize(position: position, directions: .all)
    }
}

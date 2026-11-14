import AppKit

/// Canvas của editor: hiện ảnh đã chụp, lớp tối, vùng chọn, nét vẽ và hai thanh công cụ.
/// Dùng chung cho overlay (tỉ lệ 1:1) và cửa sổ ảnh ghép (ảnh thu nhỏ cho vừa cửa sổ).
///
/// Vùng chọn và nét vẽ lưu theo point của canvas, gốc trên-trái. Ảnh, lớp tối, viền và tay nắm
/// đều là view dùng layer, nên kéo vùng chọn chỉ là đổi frame. Chỉ nét vẽ mới cần `draw(_:)`,
/// và view vẽ đó chỉ được tạo khi có nét vẽ đầu tiên.
final class EditorView: NSView {
    // MARK: Cấu hình

    let image: CGImage
    /// Số pixel ảnh trên mỗi point canvas.
    let pixelScale: CGFloat
    /// Số pixel ảnh xuất ra trên mỗi point canvas: 1 khi bật Downscale Retina.
    private let outputScale: CGFloat
    let canvasSize: CGSize
    private let inset: CGFloat

    // MARK: Callback về phiên chụp

    var shouldBeginSelection: () -> Bool = { true }
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onClose: () -> Void = {}

    // MARK: Vùng chọn

    private(set) var selection: CGRect? {
        didSet {
            layoutChrome()
            canvas?.needsDisplay = true
        }
    }

    /// Chỉ được chọn lại vùng từ đầu khi chưa có nét vẽ nào.
    var canReselect: Bool { annotations.isEmpty && inProgress == nil && editingText == nil }

    enum Drag {
        case creating(anchor: CGPoint)
        case moving(grab: CGPoint, start: CGRect)
        case resizing(SelectionHandle, start: CGRect)
        case drawing(anchor: CGPoint)
        case movingText(id: Int, grab: CGPoint, origin: CGPoint, before: [Annotation])
        case resizingText(id: Int, anchor: CGPoint, corner: CGPoint, fontSize: CGFloat, before: [Annotation])
    }

    var drag: Drag?
    /// Lần kéo text hiện tại đã thực sự đổi gì chưa (để quyết định có ghi Undo).
    var dragChanged = false

    /// Khung của canvas trong view, và tỉ lệ point view / point canvas.
    private var canvasFrame = CGRect.zero
    private(set) var zoom: CGFloat = 1

    // MARK: Nét vẽ

    var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private(set) var nextID = 1
    private var inProgress: Annotation?
    private var pixelCache: [Int: (rect: CGRect, image: CGImage)] = [:]

    private(set) var tool: Tool?
    private(set) var color = Prefs.color
    private var strokeSize = Prefs.strokeSize

    // MARK: Text

    var selectedTextID: Int? {
        didSet {
            if selectedTextID != oldValue { redraw() }
        }
    }

    var editingText: TextEditing?
    /// Text đang được đổi màu liên tục từ bảng màu: chỉ ghi Undo một lần.
    private var recoloringTextID: Int?

    // MARK: View con

    private let imageView = NSView()
    private let dimViews = (0..<4).map { _ in NSView() }
    private var canvas: AnnotationCanvas?
    private let borderOuter = NSView()
    private let borderInner = NSView()
    private let handleViews = SelectionHandle.all.map { _ in NSView() }
    private let sizeBox = NSView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let toolBar = BarView(vertical: true)
    private let actionBar = BarView(vertical: false)
    private var toolButtons: [Tool: BarButton] = [:]
    private var colorButton: BarButton?
    private var sizeButton: BarButton?

    init(image: CGImage, pixelScale: CGFloat, canvasSize: CGSize, inset: CGFloat = 0) {
        self.image = image
        self.pixelScale = pixelScale
        self.outputScale = Prefs.downscaleRetina ? 1 : pixelScale
        self.canvasSize = canvasSize
        self.inset = inset
        super.init(frame: CGRect(x: 0, y: 0, width: canvasSize.width + 2 * inset, height: canvasSize.height + 2 * inset))
        wantsLayer = true

        imageView.wantsLayer = true
        imageView.layerContentsRedrawPolicy = .never
        imageView.layer?.contents = image
        imageView.layer?.contentsGravity = .resize
        imageView.layer?.minificationFilter = .trilinear
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
            view.layer?.cornerRadius = SelectionHandle.size / 2
            addSubview(view)
        }

        sizeBox.wantsLayer = true
        sizeBox.layer?.backgroundColor = NSColor(white: 0, alpha: 0.7).cgColor
        sizeBox.layer?.cornerRadius = 4
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white
        sizeBox.addSubview(sizeLabel)
        addSubview(sizeBox)

        for tool in Tool.allCases {
            toolButtons[tool] = toolBar.addButton(symbol: tool.symbol, tooltip: tool.title) { [weak self] in
                self?.toggleTool(tool)
            }
        }
        colorButton = toolBar.addButton(image: .swatch(color), tooltip: "Màu") { [weak self] in
            self?.showColorPanel()
        }
        sizeButton = toolBar.addButton(image: .strokeDot(strokeSize), tooltip: "Độ dày nét: \(strokeSize.title)") { [weak self] in
            self?.cycleStrokeSize()
        }
        addSubview(toolBar)

        actionBar.addButton(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)") { [weak self] in self?.requestSave() }
        actionBar.addButton(symbol: "doc.on.doc", tooltip: "Copy (⌘C)") { [weak self] in self?.requestCopy() }
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

    /// Click vào overlay ở màn hình khác (panel chưa là key) vẫn có tác dụng ngay.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func clearSelection() {
        drag = nil
        selection = nil
    }

    /// Chọn sẵn toàn bộ ảnh (chụp toàn màn hình, chụp nhiều màn hình).
    func selectAll() {
        selection = CGRect(origin: .zero, size: canvasSize)
    }

    /// Ảnh xuất ra: vùng chọn cắt từ ảnh gốc, đã gộp nét vẽ.
    func renderSelection() -> CGImage? {
        commitText()
        guard let selection else { return nil }
        return Exporter.render(
            image: image, pixelScale: pixelScale, outputScale: outputScale, selection: selection, annotations: annotations
        ) { [self] in pixelImage(for: $0) }
    }

    /// Dọn editor khi phiên kết thúc: bỏ ô nhập text đang gõ dở và nhả ảnh đã chụp.
    func tearDown() {
        if let textView = editingText?.view {
            editingText = nil
            textView.delegate = nil
            window?.makeFirstResponder(nil)
            textView.removeFromSuperview()
        }
        imageView.layer?.contents = nil
        pixelCache.removeAll()
    }

    /// Gỡ bảng màu của hệ thống khỏi editor đang đóng.
    static func dismissColorPanel() {
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
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
        if let canvas {
            canvas.frame = canvasFrame
            canvas.bounds = CGRect(origin: .zero, size: canvasSize)
        }
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

    /// Đặt lại lớp tối, viền, tay nắm, nhãn kích thước và hai thanh theo vùng chọn hiện tại.
    private func layoutChrome() {
        var creating = false
        if case .creating = drag { creating = true }

        guard let selection else {
            dimViews[0].frame = canvasFrame
            dimViews[1...].forEach { $0.frame = .zero }
            ([borderOuter, borderInner, sizeBox, toolBar, actionBar] + handleViews).forEach { $0.isHidden = true }
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

        for (handle, view) in zip(SelectionHandle.all, handleViews) {
            let p = handle.point(in: r)
            let size = SelectionHandle.size
            view.frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            view.isHidden = creating
        }

        let width = Int((selection.width * outputScale).rounded())
        let height = Int((selection.height * outputScale).rounded())
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

        toolBar.isHidden = creating
        actionBar.isHidden = creating
        if !creating {
            let placed = BarLayout.place(
                selection: r, bounds: bounds, toolSize: toolBar.frame.size, actionSize: actionBar.frame.size
            )
            if let tool = placed.tool { toolBar.setFrameOrigin(tool.origin) }
            actionBar.setFrameOrigin(placed.action.origin)
        }
    }

    // MARK: Canvas nét vẽ

    /// View vẽ nét, toạ độ trùng với canvas. Tạo khi cần lần đầu để phiên chỉ chụp-rồi-copy không tốn bộ nhớ.
    @discardableResult
    func ensureCanvas() -> AnnotationCanvas {
        if let canvas { return canvas }
        let canvas = AnnotationCanvas()
        canvas.onDraw = { [weak self] ctx in self?.drawCanvas(in: ctx) }
        canvas.frame = canvasFrame
        canvas.bounds = CGRect(origin: .zero, size: canvasSize)
        addSubview(canvas, positioned: .above, relativeTo: dimViews.last)
        self.canvas = canvas
        return canvas
    }

    /// Vẽ lại vùng `rect` của canvas (toạ độ canvas), hoặc toàn bộ nếu không truyền.
    func redraw(_ rect: CGRect? = nil) {
        guard let canvas else { return }
        if let rect {
            canvas.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
        } else {
            canvas.needsDisplay = true
        }
    }

    private func drawCanvas(in ctx: CGContext) {
        guard let selection else { return }
        ctx.saveGState()
        ctx.clip(to: selection)
        for annotation in annotations where annotation.id != editingText?.id {
            annotation.draw(in: ctx) { pixelImage(for: $0) }
        }
        inProgress?.draw(in: ctx) { pixelImage(for: $0) }
        ctx.restoreGState()
        drawTextChrome(in: ctx)
    }

    private func pixelImage(for annotation: Annotation) -> CGImage? {
        guard case .pixelate(let rect) = annotation.shape, rect.width >= 1, rect.height >= 1 else { return nil }
        if let cached = pixelCache[annotation.id], cached.rect == rect { return cached.image }
        guard let pixelated = Pixelator.image(of: rect, in: image, pixelScale: pixelScale) else { return nil }
        pixelCache[annotation.id] = (rect, pixelated)
        return pixelated
    }

    // MARK: Undo / Redo

    func index(of id: Int) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    /// Ghi lại trạng thái hiện tại trước khi sửa nét vẽ.
    func pushUndo(_ state: [Annotation]? = nil) {
        undoStack.append(state ?? annotations)
        redoStack.removeAll()
        recoloringTextID = nil
    }

    /// Thêm một nét vẽ mới (có ghi Undo).
    func commit(_ annotation: Annotation) {
        pushUndo()
        annotations.append(annotation)
        nextID += 1
        ensureCanvas()
        redraw(annotation.bounds)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        restore(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        restore(next)
    }

    private func restore(_ state: [Annotation]) {
        annotations = state
        recoloringTextID = nil
        if let id = selectedTextID, index(of: id) == nil {
            selectedTextID = nil
        }
        let alive = Set(state.map(\.id))
        pixelCache = pixelCache.filter { alive.contains($0.key) }
        redraw()
    }

    // MARK: Thanh công cụ

    private func toggleTool(_ newTool: Tool) {
        commitText()
        tool = tool == newTool ? nil : newTool
        for (key, button) in toolButtons {
            button.isSelected = key == tool
        }
        if tool != nil, tool != .text {
            selectedTextID = nil
        }
    }

    private func cycleStrokeSize() {
        strokeSize = strokeSize.next
        Prefs.strokeSize = strokeSize
        sizeButton?.image = .strokeDot(strokeSize)
        sizeButton?.toolTip = "Độ dày nét: \(strokeSize.title)"
    }

    private func showColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        // Bảng màu phải nổi trên overlay và hiện được ở mọi desktop, kể cả space full màn hình.
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, (window?.level.rawValue ?? 0) + 1))
        panel.joinAllSpaces()
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        let newColor = sender.color.usingColorSpace(.sRGB) ?? sender.color
        color = newColor
        Prefs.color = newColor
        colorButton?.image = .swatch(newColor)

        // Màu mới áp dụng luôn cho text đang gõ hoặc đang chọn.
        if let editing = editingText {
            editing.view.textColor = newColor
            editing.view.insertionPointColor = newColor
        } else if let id = selectedTextID, let index = index(of: id) {
            if recoloringTextID != id {
                pushUndo()
                recoloringTextID = id
            }
            annotations[index].color = newColor
            redraw()
        }
    }

    private func requestCopy() {
        commitText()
        guard selection != nil else { return }
        onCopy()
    }

    private func requestSave() {
        commitText()
        guard selection != nil else { return }
        onSave()
    }

    // MARK: Chuột

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(p) else { return nil }
        for bar in [toolBar, actionBar] where !bar.isHidden && bar.frame.contains(p) {
            return bar.hitTest(p) ?? bar
        }
        // Click trong ô đang gõ text thì để ô đó tự xử lý.
        if let textView = editingText?.view, textView.convert(textView.bounds, to: self).contains(p) {
            return textView
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

    private func handle(at v: CGPoint) -> SelectionHandle? {
        guard let selection else { return nil }
        let r = viewRect(selection)
        return SelectionHandle.all.first { handle in
            let p = handle.point(in: r)
            return abs(p.x - v.x) <= SelectionHandle.hitRadius && abs(p.y - v.y) <= SelectionHandle.hitRadius
        }
    }

    /// Làm tròn các cạnh theo lưới pixel của ảnh xuất ra để ảnh không lệch pixel.
    private func snapped(_ rect: CGRect) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value * outputScale).rounded() / outputScale }
        let x0 = snap(rect.minX), y0 = snap(rect.minY)
        return CGRect(x: x0, y: y0, width: snap(rect.maxX) - x0, height: snap(rect.maxY) - y0)
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    override func mouseDown(with event: NSEvent) {
        let v = viewPoint(event)
        let p = canvasPoint(v)

        // Đang gõ text mà click ra ngoài: chỉ chốt text.
        if editingText != nil {
            commitText()
            return
        }
        if let selection, let handle = handle(at: v) {
            drag = .resizing(handle, start: selection)
            return
        }
        if tool == nil || tool == .text, beginTextDrag(at: p, clickCount: event.clickCount) {
            return
        }
        selectedTextID = nil

        if let selection, viewRect(selection).contains(v) {
            if let tool {
                beginDrawing(tool, at: p)
            } else {
                drag = .moving(grab: p, start: selection)
                NSCursor.closedHand.set()
            }
            return
        }
        guard canReselect, canvasFrame.contains(v), shouldBeginSelection() else { return }
        drag = .creating(anchor: p)
        selection = nil
        NSCursor.crosshair.set()
    }

    private func beginDrawing(_ tool: Tool, at p: CGPoint) {
        // Độ dày, cỡ chữ, cỡ hình tròn chọn theo point trên màn hình. Khi ảnh đang thu nhỏ (cửa sổ ảnh ghép),
        // quy đổi ra point của canvas để nét vẽ trông giống nhau ở mọi mức thu phóng.
        let unit = 1 / zoom
        func make(_ shape: Annotation.Shape) -> Annotation {
            Annotation(id: nextID, shape: shape, color: color, lineWidth: strokeSize.lineWidth * unit)
        }
        switch tool {
        case .text:
            beginEditingText(id: nil, at: p, string: "", fontSize: (Annotation.defaultFontSize * unit).rounded(), color: color)
            return
        case .counter:
            let numbers = annotations.compactMap { annotation -> Int? in
                if case .counter(_, let number, _) = annotation.shape { return number }
                return nil
            }
            let radius = Annotation.counterRadius(for: strokeSize) * unit
            commit(make(.counter(center: p, number: (numbers.max() ?? 0) + 1, radius: radius)))
            return
        case .pen: inProgress = make(.stroke(points: [p], marker: false))
        case .marker: inProgress = make(.stroke(points: [p], marker: true))
        case .line: inProgress = make(.line(from: p, to: p, arrow: false))
        case .arrow: inProgress = make(.line(from: p, to: p, arrow: true))
        case .rectangle: inProgress = make(.rectangle(CGRect(origin: p, size: .zero)))
        case .pixelate: inProgress = make(.pixelate(CGRect(origin: p, size: .zero)))
        }
        drag = .drawing(anchor: p)
        ensureCanvas()
        redraw(inProgress?.bounds)
    }

    private func continueDrawing(from anchor: CGPoint, to p: CGPoint) {
        guard var current = inProgress else { return }
        var dirty = current.bounds
        switch current.shape {
        case .stroke(var points, let marker):
            guard let last = points.last, hypot(p.x - last.x, p.y - last.y) >= 1 else { return }
            points.append(p)
            current.shape = .stroke(points: points, marker: marker)
            // Nét tự do chỉ đổi ở vài điểm cuối: vẽ lại đúng vùng đó thôi.
            let width = current.strokeWidth
            dirty = Annotation.boundingBox(points.suffix(4)).insetBy(dx: -width, dy: -width)
        case .line(let from, _, let arrow):
            current.shape = .line(from: from, to: p, arrow: arrow)
            dirty = dirty.union(current.bounds)
        case .rectangle:
            current.shape = .rectangle(rect(from: anchor, to: p))
            dirty = dirty.union(current.bounds)
        case .pixelate:
            current.shape = .pixelate(rect(from: anchor, to: p))
            dirty = dirty.union(current.bounds)
        case .counter, .text:
            return
        }
        inProgress = current
        redraw(dirty)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = canvasPoint(viewPoint(event))
        switch drag {
        case .creating(let anchor):
            let rect = snapped(rect(from: anchor, to: p))
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

        case .drawing(let anchor):
            continueDrawing(from: anchor, to: p)

        case .movingText, .resizingText:
            dragText(drag, to: p)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let finished = drag else { return }
        drag = nil
        switch finished {
        case .creating:
            // Click hoặc kéo quá ngắn thì coi như chưa chọn.
            if let selection, selection.width < 3 || selection.height < 3 {
                self.selection = nil
            } else {
                layoutChrome()
            }
        case .moving, .resizing:
            break
        case .drawing:
            if let done = inProgress {
                inProgress = nil
                if done.isMeaningful {
                    commit(done)
                } else {
                    pixelCache[done.id] = nil
                    redraw(done.bounds)
                }
            }
        case .movingText(_, _, _, let before), .resizingText(_, _, _, _, let before):
            if dragChanged { pushUndo(before) }
        }
        dragChanged = false
        updateCursor(at: viewPoint(event))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: viewPoint(event))
    }

    private func updateCursor(at v: CGPoint) {
        guard drag == nil else { return }
        let p = canvasPoint(v)
        let cursor: NSCursor
        if [toolBar, actionBar].contains(where: { !$0.isHidden && $0.frame.contains(v) }) {
            cursor = .arrow
        } else if let textView = editingText?.view {
            cursor = textView.convert(textView.bounds, to: self).contains(v) ? .iBeam : .arrow
        } else if let selection {
            if let handle = handle(at: v) {
                cursor = handle.cursor
            } else if tool == nil || tool == .text, let textCursor = textCursor(at: p) {
                cursor = textCursor
            } else if viewRect(selection).contains(v) {
                switch tool {
                case nil: cursor = .openHand
                case .text: cursor = .iBeam
                default: cursor = .crosshair
                }
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
        switch event.keyCode {
        case 53: onClose() // Esc
        case 51, 117: deleteSelectedText() // Delete, Forward Delete
        default: break // Nuốt các phím khác để không kêu "beep".
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.contains(.command) else { return super.performKeyEquivalent(with: event) }
        // Không để phím tắt ⌘ rơi xuống main menu (⌘H, ⌘Q…) khi editor đang mở.
        guard drag == nil, modifiers == .command || modifiers == [.command, .shift] else { return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift = modifiers.contains(.shift)

        // Đang gõ text: các phím soạn thảo tác động lên ô nhập.
        if editingText != nil, let action = Self.textAction(key: key, shift: shift) {
            NSApp.sendAction(action, to: nil, from: self)
            return true
        }
        switch (key, shift) {
        case ("c", false): requestCopy()
        case ("s", false): requestSave()
        case ("z", false): undo()
        case ("z", true): redo()
        case ("w", false): onClose()
        default: break
        }
        return true
    }

    private static func textAction(key: String, shift: Bool) -> Selector? {
        switch (key, shift) {
        case ("c", false): #selector(NSText.copy(_:))
        case ("x", false): #selector(NSText.cut(_:))
        case ("v", false): #selector(NSText.paste(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        default: nil
        }
    }
}

/// View vẽ nét của editor. Bản thân không giữ dữ liệu, chỉ gọi lại `EditorView` để vẽ.
final class AnnotationCanvas: NSView {
    var onDraw: ((CGContext) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        onDraw?(ctx)
    }
}

/// Một trong 8 tay nắm resize của vùng chọn.
struct SelectionHandle {
    /// -1: cạnh trái/trên, 0: giữa, 1: cạnh phải/dưới.
    let x: Int
    let y: Int

    static let size: CGFloat = 9
    static let hitRadius: CGFloat = 7
    /// Góc trước, cạnh sau: vùng chọn nhỏ thì ưu tiên bắt tay nắm góc.
    static let all = [(-1, -1), (1, -1), (-1, 1), (1, 1), (0, -1), (-1, 0), (1, 0), (0, 1)]
        .map { SelectionHandle(x: $0.0, y: $0.1) }

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

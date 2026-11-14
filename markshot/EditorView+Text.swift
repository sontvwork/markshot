import AppKit

/// Ô nhập text đang mở. `id` là text có sẵn đang được sửa, `nil` nếu là text mới.
struct TextEditing {
    let view: NSTextView
    let id: Int?
}

/// Công cụ Text: gõ tại chỗ, rồi chọn, kéo, resize, sửa, xoá.
extension EditorView: NSTextViewDelegate {
    /// 1 point màn hình tính theo đơn vị canvas, để viền và tay nắm không to nhỏ theo zoom.
    private var unit: CGFloat { 1 / zoom }

    private func textAnnotation(at p: CGPoint) -> Annotation? {
        annotations.last { $0.textFrame?.insetBy(dx: -4 * unit, dy: -4 * unit).contains(p) == true }
    }

    /// Khung viền chọn bao quanh text.
    private func chromeBox(_ frame: CGRect) -> CGRect {
        frame.insetBy(dx: -4 * unit, dy: -4 * unit)
    }

    /// Tay nắm góc tại `p`: trả về góc đó của khung text và góc đối diện (điểm neo khi resize).
    private func textCorner(at p: CGPoint, of frame: CGRect) -> (corner: CGPoint, anchor: CGPoint)? {
        let box = chromeBox(frame)
        let radius = 8 * unit
        for (left, top) in [(true, true), (false, true), (true, false), (false, false)] {
            let handle = CGPoint(x: left ? box.minX : box.maxX, y: top ? box.minY : box.maxY)
            guard abs(handle.x - p.x) <= radius, abs(handle.y - p.y) <= radius else { continue }
            return (
                CGPoint(x: left ? frame.minX : frame.maxX, y: top ? frame.minY : frame.maxY),
                CGPoint(x: left ? frame.maxX : frame.minX, y: top ? frame.maxY : frame.minY)
            )
        }
        return nil
    }

    private var selectedTextFrame: CGRect? {
        guard let id = selectedTextID, let index = index(of: id) else { return nil }
        return annotations[index].textFrame
    }

    // MARK: Chọn, kéo, resize

    /// Xử lý mouse-down trên text: tay nắm góc → resize, click → chọn và kéo, double-click → sửa.
    /// Trả về `false` nếu điểm đó không trúng text nào.
    func beginTextDrag(at p: CGPoint, clickCount: Int) -> Bool {
        if let id = selectedTextID, let index = index(of: id),
           case .text(_, _, let fontSize) = annotations[index].shape,
           let frame = annotations[index].textFrame, let hit = textCorner(at: p, of: frame) {
            drag = .resizingText(id: id, anchor: hit.anchor, corner: hit.corner, fontSize: fontSize, before: annotations)
            return true
        }
        guard let hit = textAnnotation(at: p), case .text(let origin, let string, let fontSize) = hit.shape else {
            return false
        }
        selectedTextID = hit.id
        if clickCount >= 2 {
            beginEditingText(id: hit.id, at: origin, string: string, fontSize: fontSize, color: hit.color)
        } else {
            drag = .movingText(id: hit.id, grab: p, origin: origin, before: annotations)
        }
        return true
    }

    func dragText(_ drag: Drag, to p: CGPoint) {
        switch drag {
        case .movingText(let id, let grab, let origin, _):
            guard let index = index(of: id), case .text(_, let string, let fontSize) = annotations[index].shape else { return }
            let moved = CGPoint(x: origin.x + p.x - grab.x, y: origin.y + p.y - grab.y)
            annotations[index].shape = .text(origin: moved, string: string, fontSize: fontSize)

        case .resizingText(let id, let anchor, let corner, let fontSize, _):
            guard let index = index(of: id), case .text(_, let string, _) = annotations[index].shape else { return }
            let base = hypot(corner.x - anchor.x, corner.y - anchor.y)
            guard base > 0 else { return }
            // Cỡ chữ đổi theo khoảng cách từ con trỏ tới góc đối diện; góc đối diện đứng yên.
            let scaled = fontSize * hypot(p.x - anchor.x, p.y - anchor.y) / base
            let newSize = min(max(scaled.rounded(), 8), 400)
            let size = Annotation.textSize(string, fontSize: newSize)
            let origin = CGPoint(
                x: corner.x >= anchor.x ? anchor.x : anchor.x - size.width,
                y: corner.y >= anchor.y ? anchor.y : anchor.y - size.height
            )
            annotations[index].shape = .text(origin: origin, string: string, fontSize: newSize)

        default:
            return
        }
        dragChanged = true
        redraw()
    }

    /// Con trỏ khi rê chuột lên text hoặc tay nắm của text; `nil` nếu không trúng.
    func textCursor(at p: CGPoint) -> NSCursor? {
        if let frame = selectedTextFrame, let hit = textCorner(at: p, of: frame) {
            let left = hit.corner.x < hit.anchor.x, top = hit.corner.y < hit.anchor.y
            let position: NSCursor.FrameResizePosition = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
            return .frameResize(position: position, directions: .all)
        }
        return textAnnotation(at: p) == nil ? nil : .openHand
    }

    func deleteSelectedText() {
        guard let id = selectedTextID, let index = index(of: id) else { return }
        pushUndo()
        annotations.remove(at: index)
        selectedTextID = nil
        redraw()
    }

    // MARK: Gõ text

    /// Mở ô nhập. Text mới (`id == nil`): `point` là chỗ click, dòng chữ căn giữa theo điểm đó.
    /// Text có sẵn: `point` là góc trên-trái của text.
    func beginEditingText(id: Int?, at point: CGPoint, string: String, fontSize: CGFloat, color: NSColor) {
        let canvas = ensureCanvas()
        let font = Annotation.textFont(size: fontSize)
        let textView = NSTextView(usingTextLayoutManager: false)
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? fontSize * 1.2
        textView.frame.origin = id == nil ? CGPoint(x: point.x, y: point.y - lineHeight / 2) : point

        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
        // Không lề, không đệm: chữ trong ô nhập nằm đúng chỗ nó sẽ được vẽ sau khi chốt.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.string = string
        textView.delegate = self

        canvas.addSubview(textView)
        editingText = TextEditing(view: textView, id: id)
        fitTextView()
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }

    /// Chốt text đang gõ. Text rỗng thì bỏ (nếu đang sửa text có sẵn thì xoá nó).
    func commitText() {
        guard let editing = editingText else { return }
        editingText = nil
        let textView = editing.view
        let string = textView.string
        let origin = textView.frame.origin
        let fontSize = textView.font?.pointSize ?? Annotation.defaultFontSize
        let textColor = textView.textColor ?? color
        textView.delegate = nil
        textView.removeFromSuperview()
        window?.makeFirstResponder(self)

        let isBlank = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let id = editing.id, let index = index(of: id) {
            if isBlank {
                pushUndo()
                annotations.remove(at: index)
                selectedTextID = nil
            } else if case .text(_, let oldString, _) = annotations[index].shape,
                      oldString != string || annotations[index].color != textColor {
                pushUndo()
                annotations[index].shape = .text(origin: origin, string: string, fontSize: fontSize)
                annotations[index].color = textColor
            }
        } else if !isBlank {
            let id = nextID
            commit(Annotation(id: id, shape: .text(origin: origin, string: string, fontSize: fontSize), color: textColor, lineWidth: 0))
            selectedTextID = id
        }
        redraw()
    }

    /// Co giãn ô nhập cho vừa nội dung.
    private func fitTextView() {
        guard let textView = editingText?.view,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let font = textView.font ?? Annotation.textFont(size: Annotation.defaultFontSize)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        // Chừa thêm một ký tự bề ngang cho con trỏ và chữ đang gõ dở (bộ gõ tiếng Việt).
        textView.setFrameSize(NSSize(
            width: ceil(used.width) + font.pointSize,
            height: ceil(max(used.height, lineHeight))
        ))
        redraw()
    }

    func textDidChange(_ notification: Notification) {
        fitTextView()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc khi đang gõ: chốt text chứ không đóng editor. (NSTextView có thể đổi Esc thành `complete:`.)
        guard commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSTextView.complete(_:)) else { return false }
        commitText()
        return true
    }

    // MARK: Vẽ khung chọn

    /// Viền đứt quanh text đang gõ hoặc đang chọn, kèm 4 tay nắm góc khi đang chọn.
    func drawTextChrome(in ctx: CGContext) {
        let frame: CGRect
        let showsHandles: Bool
        if let editing = editingText {
            frame = editing.view.frame
            showsHandles = false
        } else if let selected = selectedTextFrame {
            frame = selected
            showsHandles = true
        } else {
            return
        }

        let box = chromeBox(frame)
        ctx.setLineWidth(unit)
        ctx.setStrokeColor(NSColor(white: 0, alpha: 0.6).cgColor)
        ctx.stroke(box)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
        ctx.stroke(box)
        ctx.setLineDash(phase: 0, lengths: [])

        guard showsHandles else { return }
        let side = 7 * unit
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor(white: 0, alpha: 0.7).cgColor)
        for corner in [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
        ] {
            let handle = CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side)
            ctx.fill(handle)
            ctx.stroke(handle)
        }
    }
}

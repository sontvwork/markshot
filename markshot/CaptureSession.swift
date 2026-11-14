import AppKit

/// Cửa sổ không viền phủ kín một màn hình, nằm trên menu bar, Dock và app full màn hình.
final class OverlayPanel: NSPanel {
    /// Trên menu bar/Dock nhưng dưới tooltip, để tooltip của thanh công cụ vẫn hiện.
    static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Con trỏ do EditorView tự đặt theo vị trí chuột.
        disableCursorRects()
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Cửa sổ thường chứa editor của ảnh toàn màn hình / ghép nhiều màn hình, thu phóng cho vừa màn hình đang dùng.
final class EditorWindow: NSWindow {
    /// Lề quanh ảnh, đủ chỗ cho hai thanh công cụ nằm ngoài ảnh khi vùng chọn là cả ảnh.
    static let inset: CGFloat = 56
    private static let minimumContentSize = NSSize(width: 520, height: 460)

    init(canvasSize: CGSize) {
        let visible = NSScreen.underMouse?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        // Ảnh được thu nhỏ cho vừa khoảng 90% màn hình, không phóng to quá 1:1.
        let room = CGSize(
            width: visible.width * 0.9 - 2 * Self.inset,
            height: visible.height * 0.9 - 2 * Self.inset - 32
        )
        let zoom = min(room.width / canvasSize.width, room.height / canvasSize.height, 1)
        let content = NSSize(
            width: max((canvasSize.width * zoom).rounded() + 2 * Self.inset, Self.minimumContentSize.width),
            height: max((canvasSize.height * zoom).rounded() + 2 * Self.inset, Self.minimumContentSize.height)
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "markshot"
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = NSColor(white: 0.16, alpha: 1)
        contentMinSize = Self.minimumContentSize
        isReleasedWhenClosed = false
        disableCursorRects()
        setFrameOrigin(NSPoint(
            x: (visible.midX - frame.width / 2).rounded(),
            y: (visible.midY - frame.height / 2).rounded()
        ))
    }
}

/// Một phiên chụp: các cửa sổ editor đang mở và việc Copy / Save / đóng.
/// Mỗi lúc chỉ có một vùng chọn hoạt động, dù overlay phủ nhiều màn hình.
final class CaptureSession: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var editors: [EditorView] = []
    private let previousApp: NSRunningApplication?
    private let onEnd: () -> Void
    private var ended = false
    /// Hộp thoại Save đang mở: tạm khoá Copy, Đóng và việc chọn lại vùng ở các màn hình khác.
    private var isSaving = false

    private init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? nil : front
        super.init()
    }

    /// Overlay: mỗi màn hình đã chụp một panel phủ kín, hiển thị đúng ảnh vừa chụp.
    convenience init(overlay shots: [ScreenShot], onEnd: @escaping () -> Void) {
        self.init(onEnd: onEnd)
        for shot in shots {
            let editor = EditorView(image: shot.image, pixelScale: shot.scale, canvasSize: shot.screen.frame.size)
            attach(editor, to: OverlayPanel(screen: shot.screen))
        }

        // Ảnh đã chụp xong nên kích hoạt app lúc này không làm đổi nội dung "đóng băng".
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows[0]
        for window in windows where window !== keyWindow {
            window.orderFrontRegardless()
        }
        keyWindow.makeKeyAndOrderFront(nil)
        for window in windows {
            window.makeFirstResponder(window.contentView)
        }
        NSCursor.crosshair.set()

        // Cắm/rút màn hình giữa chừng thì overlay không còn khớp: huỷ phiên.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Cửa sổ editor riêng cho ảnh toàn màn hình / ghép nhiều màn hình, chọn sẵn toàn bộ ảnh.
    convenience init(stitched shot: StitchedShot, onEnd: @escaping () -> Void) {
        self.init(onEnd: onEnd)
        let editor = EditorView(
            image: shot.image, pixelScale: shot.scale, canvasSize: shot.canvasSize, inset: EditorWindow.inset
        )
        let window = EditorWindow(canvasSize: shot.canvasSize)
        window.delegate = self
        attach(editor, to: window)
        editor.selectAll()
        window.presentOnTop()
        window.makeFirstResponder(editor)
    }

    private func attach(_ editor: EditorView, to window: NSWindow) {
        editor.shouldBeginSelection = { [weak self, weak editor] in
            self?.beginSelection(in: editor) ?? false
        }
        editor.onCopy = { [weak self, weak editor] in
            if let editor { self?.copy(from: editor) }
        }
        editor.onSave = { [weak self, weak editor] in
            if let editor { self?.save(from: editor) }
        }
        editor.onClose = { [weak self] in
            if self?.isSaving == false { self?.end() }
        }

        window.contentView = editor
        window.initialFirstResponder = editor
        windows.append(window)
        editors.append(editor)
    }

    /// Vùng chọn chỉ nằm trên một màn hình: bắt đầu chọn ở màn hình này thì bỏ vùng chọn ở màn hình khác.
    private func beginSelection(in editor: EditorView?) -> Bool {
        let others = editors.filter { $0 !== editor }
        guard !isSaving, others.allSatisfy(\.canReselect) else { return false }
        others.forEach { $0.clearSelection() }
        return true
    }

    private func copy(from editor: EditorView) {
        guard !isSaving, let image = editor.renderSelection() else { return }
        // Ẩn editor trước rồi mới nén ảnh, để thao tác Copy có cảm giác tức thì.
        windows.forEach { $0.orderOut(nil) }
        Exporter.copy(image, pointSize: editor.selection?.size ?? .zero)
        end()
    }

    private func save(from editor: EditorView) {
        guard !isSaving, let image = editor.renderSelection(), let window = editor.window else { return }
        isSaving = true
        Exporter.save(image, pointSize: editor.selection?.size ?? .zero, on: window) { [weak self, weak editor] saved in
            guard let self, !ended else { return }
            isSaving = false
            if saved {
                end()
            } else {
                // Cancel: quay lại editor, giữ nguyên nét vẽ.
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(editor)
            }
        }
    }

    @objc private func screensChanged() {
        end()
    }

    /// Nút đóng của cửa sổ editor: kết thúc phiên như bấm Esc.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !isSaving { end() }
        return false
    }

    /// Kết thúc phiên và giải phóng toàn bộ cửa sổ, ảnh.
    func end() {
        guard !ended else { return }
        ended = true
        NotificationCenter.default.removeObserver(self)
        EditorView.dismissColorPanel()
        editors.forEach { $0.tearDown() }
        for window in windows {
            window.delegate = nil
            // Phiên bị huỷ giữa chừng (cắm/rút màn hình) khi hộp thoại Save còn mở: đóng hộp thoại trước.
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        editors.removeAll()
        NSCursor.arrow.set()
        previousApp?.activate()
        onEnd()
    }
}

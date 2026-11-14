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

/// Một phiên chụp kiểu overlay: mỗi màn hình một panel, chỉ một vùng chọn đang hoạt động.
final class OverlaySession: NSObject {
    private var panels: [OverlayPanel] = []
    private var editors: [EditorView] = []
    private let previousApp: NSRunningApplication?
    private let onEnd: () -> Void
    private var ended = false

    init(shots: [ScreenShot], onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? nil : front
        super.init()

        for shot in shots {
            let editor = EditorView(image: shot.image, pixelScale: shot.scale, canvasSize: shot.screen.frame.size)
            editor.shouldBeginSelection = { [weak self, weak editor] in
                self?.beginSelection(in: editor) ?? false
            }
            editor.onCopy = { [weak self, weak editor] in
                if let editor { self?.copy(from: editor) }
            }
            editor.onClose = { [weak self] in self?.end() }

            let panel = OverlayPanel(screen: shot.screen)
            panel.contentView = editor
            panel.initialFirstResponder = editor
            panels.append(panel)
            editors.append(editor)
        }

        // Ảnh đã chụp xong nên kích hoạt app lúc này không làm đổi nội dung "đóng băng".
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels[0]
        for panel in panels where panel !== keyPanel {
            panel.orderFrontRegardless()
        }
        keyPanel.makeKeyAndOrderFront(nil)
        for panel in panels {
            panel.makeFirstResponder(panel.contentView)
        }
        NSCursor.crosshair.set()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Vùng chọn chỉ nằm trên một màn hình: bắt đầu chọn ở màn hình này thì bỏ vùng chọn ở màn hình khác.
    private func beginSelection(in editor: EditorView?) -> Bool {
        let others = editors.filter { $0 !== editor }
        guard others.allSatisfy(\.canReselect) else { return false }
        others.forEach { $0.clearSelection() }
        return true
    }

    private func copy(from editor: EditorView) {
        guard let image = editor.renderSelection() else { return }
        // Ẩn overlay trước rồi mới nén ảnh, để thao tác Copy có cảm giác tức thì.
        panels.forEach { $0.orderOut(nil) }
        Exporter.copy(image, pointSize: editor.selection?.size ?? .zero)
        end()
    }

    @objc private func screensChanged() {
        end()
    }

    /// Kết thúc phiên và giải phóng toàn bộ cửa sổ, ảnh.
    func end() {
        guard !ended else { return }
        ended = true
        NotificationCenter.default.removeObserver(self)
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        editors.removeAll()
        NSCursor.arrow.set()
        previousApp?.activate()
        onEnd()
    }
}

import AppKit

extension NSWindow {
    /// Cho cửa sổ có mặt ở mọi desktop, kể cả space của một app full màn hình — cùng cách với overlay.
    ///
    /// Mặc định cửa sổ chỉ thuộc về desktop nơi nó được mở và không được xếp vào space full màn hình.
    /// markshot chạy nền, không có icon Dock, nên macOS cũng không tự chuyển desktop về chỗ cửa sổ:
    /// mở cửa sổ khi đang ở app full màn hình là không nhìn thấy nó.
    /// (Cờ `moveToActiveSpace` không dùng được: cửa sổ vẫn bị loại khỏi space full màn hình.)
    func joinAllSpaces() {
        var behavior = collectionBehavior
        behavior.remove([.moveToActiveSpace, .fullScreenPrimary, .fullScreenNone])
        behavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        collectionBehavior = behavior
    }

    /// Hiện cửa sổ nổi trên các cửa sổ thường, ngay tại desktop đang dùng.
    ///
    /// Không trông vào việc macOS có chịu kích hoạt app hay không: app chạy nền không có icon Dock
    /// hay bị từ chối, khi đó cửa sổ thường sẽ mở ra phía sau app đang dùng.
    func presentOnTop() {
        level = .floating
        joinAllSpaces()
        orderFrontRegardless()
        makeKey()
        // Kích hoạt sau khi cửa sổ đã nằm ở desktop này, để macOS không có lý do chuyển desktop.
        NSApp.activate(ignoringOtherApps: true)
    }
}

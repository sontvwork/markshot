# markshot

App chụp màn hình + vẽ chú thích kiểu Lightshot cho macOS. Dùng cá nhân, không phát hành, không lên App Store.

Đặc tả chức năng đầy đủ: **[SPEC.md](SPEC.md)**. Đọc trước khi code.

Trao đổi với tôi bằng tiếng Việt.

## Ưu tiên số 1

App chạy nền 24/7 để chờ hotkey, nên:

- **Khi chờ:** RAM thấp nhất có thể, CPU ~0%. Chỉ phản ứng theo sự kiện, không timer, không polling.
- **Khi bấm hotkey:** overlay phải hiện gần như tức thì.
- **Sau mỗi lần chụp:** giải phóng tài nguyên (ảnh, cửa sổ) để RAM quay về mức nền.

Khi phải chọn giữa các cách làm, ưu tiên cách nhẹ hơn và ít code hơn.

## Quyết định đã chốt

Không tự ý thay đổi các quyết định dưới đây. Nếu thấy có lý do kỹ thuật chính đáng để đổi, hỏi tôi trước.

### Nền tảng

- Chỉ macOS. Hỗ trợ **macOS 26 và 27** (deployment target 26.0). Code bằng **Swift**, project tạo bằng Xcode 27.
- Bundle ID `com.son.markshot`, ký bằng Personal Team (Development).
- **Không dùng App Sandbox.**
- Agent app (`LSUIElement = YES`): không có icon trên Dock, chỉ có icon trên menu bar.

### Stack

| Việc | Dùng |
|---|---|
| Icon menu bar + Preferences | SwiftUI `MenuBarExtra` + `Settings`, lưu bằng `@AppStorage` |
| Hotkey toàn cục + ô đổi hotkey | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| Chụp màn hình | ScreenCaptureKit |
| Overlay + canvas vẽ | AppKit (`NSPanel`, `NSView`) + Core Graphics |
| Chọn màu | `NSColorPanel` |
| Xuất ảnh | `NSBitmapImageRep`, `NSPasteboard`, `NSSavePanel` |
| Tự chạy khi đăng nhập | `SMAppService` |

- **KeyboardShortcuts là thư viện ngoài duy nhất.** Muốn thêm thư viện khác thì hỏi tôi trước.
- Ngoài bảng trên, cách tổ chức code, kiến trúc và chi tiết kỹ thuật do bạn tự quyết.

## Project

- Thư mục `markshot/` là thư mục đồng bộ của Xcode: chỉ cần tạo file Swift trong đó, không phải khai báo vào `.pbxproj`. Chỉ sửa `.pbxproj` khi cần đổi build setting.
- Build từ terminal để tự kiểm tra lỗi:

  ```bash
  xcodebuild -scheme markshot -configuration Debug build
  ```

- Dọn đồ thừa từ template: `ContentView`, cửa sổ `WindowGroup`, và các key iOS còn sót (*Supported interface orientations* iPad/iPhone).

## Cách làm việc

- Làm theo 4 giai đoạn. Xong giai đoạn nào thì app phải build được và chạy được tới đó:
  1. **M1:** icon menu bar + hotkey + chụp vùng chọn + Copy
  2. **M2:** đủ các công cụ vẽ + Undo/Redo
  3. **M3:** Save + Preferences + tự chạy khi đăng nhập
  4. **M4:** chụp toàn màn hình, chụp nhiều màn hình, hoàn thiện
- Cuối mỗi giai đoạn:
  1. Build không lỗi, không warning mới.
  2. Liệt kê các bước để tôi test tay (UI không test tự động được).
  3. Commit Git sau khi tôi xác nhận chạy đúng.
- Quyền Screen Recording được cấp theo chữ ký app. Đừng đổi Bundle ID hay cách ký app, nếu không tôi phải cấp lại quyền.

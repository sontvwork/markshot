# markshot — Đặc tả chức năng

## 1. Tổng quan

markshot là app chụp màn hình cho macOS, chạy nền trên menu bar. Bấm hotkey là chụp, rồi vẽ chú thích ngay trên ảnh vừa chụp, sau đó copy hoặc lưu file.

**Trong phạm vi:** chụp vùng chọn, chụp toàn màn hình, chụp nhiều màn hình, editor vẽ tại chỗ, Copy/Save, Preferences.

**Ngoài phạm vi:** upload/chia sẻ lên mạng, OCR, chụp cuộn trang, quay video, chụp theo cửa sổ, lịch sử ảnh đã chụp.

## 2. App chạy nền

### 2.1 Icon menu bar

Không có icon trên Dock. Bấm icon trên menu bar mở menu gồm:

| Mục | Hành động |
|---|---|
| Chụp vùng chọn | Như bấm hotkey chụp vùng chọn |
| Chụp toàn màn hình | Như bấm hotkey chụp toàn màn hình |
| Chụp nhiều màn hình | Như bấm hotkey chụp nhiều màn hình |
| Preferences… | Mở cửa sổ Preferences |
| Quit markshot | Thoát app |

Mỗi mục chụp hiển thị hotkey hiện tại bên cạnh.

### 2.2 Quyền Screen Recording

- Lần đầu chụp mà chưa có quyền: hiện thông báo giải thích vì sao cần quyền, kèm nút mở thẳng trang cài đặt Screen Recording trong System Settings.
- Không crash hay treo khi thiếu quyền.

### 2.3 Quy tắc chung

- Mỗi lúc chỉ có **một phiên chụp**. Đang trong phiên chụp mà bấm hotkey chụp thì bỏ qua.
- Đóng editor (Copy, Save xong, hoặc Esc) là kết thúc phiên và giải phóng toàn bộ tài nguyên của phiên.

## 3. Các chế độ chụp

### 3.1 Chụp vùng chọn — mặc định `⌥⇧4`

1. Bấm hotkey → chụp **tất cả màn hình** ngay lập tức, rồi phủ overlay lên từng màn hình. Overlay hiển thị đúng ảnh vừa chụp (màn hình như bị "đóng băng") và phủ một lớp tối mờ.
2. Kéo chuột để chọn vùng. Vùng chọn hiện sáng (không bị lớp tối), có viền, và hiển thị kích thước theo pixel (vd `640 × 480`).
3. Vùng chọn nằm trong **một màn hình**: màn hình nơi bắt đầu kéo.
4. Thả chuột → editor xuất hiện (mục 4). Vùng chọn vẫn chỉnh được:
   - **Di chuyển:** kéo bên trong vùng chọn (khi không có công cụ vẽ nào đang chọn).
   - **Resize:** kéo một trong 8 tay nắm (4 góc + 4 cạnh).
   - **Chọn lại từ đầu:** kéo ở ngoài vùng chọn, chỉ áp dụng khi chưa có nét vẽ nào.
5. `Esc` bất cứ lúc nào → hủy, đóng overlay.

### 3.2 Chụp toàn màn hình — mặc định `⌥⇧3`

- Chụp màn hình đang có con trỏ chuột.
- Mở editor giống chụp vùng chọn, vùng chọn mặc định là **toàn bộ màn hình** đó (vẫn resize/di chuyển được).

### 3.3 Chụp nhiều màn hình — mặc định `⌥⇧5`

- Chụp tất cả màn hình và **ghép thành 1 ảnh**, xếp đúng vị trí tương đối như trong System Settings → Displays.
- Phần trống giữa các màn hình (do kích thước hoặc vị trí lệch nhau): trong suốt với PNG, màu trắng với JPG.
- Các màn hình có độ phân giải/tỉ lệ khác nhau được đưa về cùng một tỉ lệ trong ảnh ghép.
- Mở ảnh ghép trong **một cửa sổ editor riêng** (cửa sổ thường, không phải overlay), tự thu phóng để vừa màn hình. Vùng chọn mặc định là toàn bộ ảnh ghép.
- Editor có đủ công cụ và hành động như mục 4 và 5.

### 3.4 Downscale Retina

Khi bật trong Preferences: ảnh xuất ra ở độ phân giải 1x (theo point) thay vì độ phân giải gốc của màn hình Retina. Áp dụng cho cả 3 chế độ chụp.

## 4. Editor

### 4.1 Bố cục

- **Thanh công cụ vẽ:** dọc, đặt cạnh phải vùng chọn.
- **Thanh hành động:** ngang, đặt dưới vùng chọn, gồm Save, Copy, Đóng.
- Hai thanh tự đổi vị trí (sang trái, lên trên hoặc vào trong vùng chọn) để không bị tràn ra ngoài màn hình.
- Hai thanh đi theo vùng chọn khi vùng chọn được di chuyển hoặc resize.

### 4.2 Công cụ vẽ

Mặc định chưa chọn công cụ nào (chế độ chỉnh vùng chọn). Bấm vào công cụ đang chọn để bỏ chọn. Mọi nét vẽ bị cắt theo vùng chọn.

| # | Công cụ | Cách dùng |
|---|---|---|
| 1 | Pen | Kéo để vẽ tự do |
| 2 | Line | Kéo từ điểm đầu đến điểm cuối |
| 3 | Arrow | Như Line, có đầu mũi tên ở điểm cuối |
| 4 | Rectangle | Kéo để vẽ hình chữ nhật, chỉ có viền |
| 5 | Marker | Như Pen nhưng nét to, bán trong suốt, dùng để highlight |
| 6 | Text | Xem mục 4.3 |
| 7 | Pixelate | Kéo hình chữ nhật, vùng đó bị làm vỡ hạt để che thông tin |
| 8 | Đánh số bước | Mỗi click đặt một hình tròn có số, tự tăng từ 1 (①②③…). Số bắt đầu lại từ 1 ở mỗi phiên chụp |
| 9 | Color picker | Mở bảng chọn màu của hệ thống |

**Màu:**

- Mặc định là màu đỏ.
- Màu đã chọn áp dụng cho các nét vẽ tiếp theo, và cho text đang được chọn (nếu có).
- App nhớ màu đã chọn giữa các lần chụp.

**Độ dày nét:**

- 3 mức S / M / L, mặc định M. App nhớ mức đã chọn giữa các lần chụp.
- Áp dụng cho Pen, Line, Arrow, Rectangle, Marker và kích thước hình tròn đánh số.

### 4.3 Text

1. Chọn công cụ Text, click vào vị trí bất kỳ → hiện ô nhập, gõ chữ.
2. Click ra ngoài hoặc bấm `Esc` → chốt text. Text rỗng thì bỏ.
3. Sau khi chốt, text vẫn chỉnh được:
   - **Chọn:** click vào text (không cần đang chọn công cụ Text).
   - **Di chuyển:** kéo text.
   - **Resize:** kéo tay nắm ở góc, cỡ chữ thay đổi theo.
   - **Sửa nội dung:** double-click.
   - **Xóa:** chọn rồi bấm `Delete`.
4. Font: font hệ thống. Không bắt buộc cho đổi font.

Các object khác (nét vẽ, hình, số) không bắt buộc chỉnh sửa sau khi vẽ. Muốn sửa thì Undo.

### 4.4 Undo / Redo

- `⌘Z` hoàn tác, `⌘⇧Z` làm lại.
- Áp dụng cho mọi thao tác vẽ, cũng như tạo, sửa, di chuyển, resize, xóa text.
- Không áp dụng cho việc di chuyển/resize vùng chọn.

### 4.5 Phím tắt trong editor

| Phím | Hành động |
|---|---|
| `Esc` | Hủy, đóng editor không lưu (khi đang gõ text: chốt text) |
| `⌘C` | Copy rồi đóng editor |
| `⌘S` | Save |
| `⌘Z` / `⌘⇧Z` | Undo / Redo |
| `Delete` | Xóa text đang chọn |

## 5. Xuất ảnh

Ảnh xuất ra luôn là **vùng chọn + toàn bộ nét vẽ đã gộp vào ảnh**, áp dụng tùy chọn downscale Retina nếu đang bật.

### 5.1 Copy

- Đưa ảnh vào clipboard, dán được vào các app thông thường (Slack, Messages, trình duyệt, Preview…).
- Xong thì đóng editor.

### 5.2 Save

1. Hiện hộp thoại lưu file của hệ thống **mỗi lần** bấm Save.
2. Thư mục mở sẵn: thư mục lưu mặc định trong Preferences.
3. Tên file mặc định: `markshot_yyyy-MM-dd_HH-mm-ss.<đuôi>`.
4. Format theo Preferences (PNG hoặc JPG, JPG dùng chất lượng đã cài).
5. Lưu thành công → đóng editor. Bấm Cancel trong hộp thoại → quay lại editor, giữ nguyên nét vẽ.

## 6. Preferences

| Nhóm | Cài đặt | Mặc định |
|---|---|---|
| Hotkey | Chụp vùng chọn | `⌥⇧4` |
| | Chụp toàn màn hình | `⌥⇧3` |
| | Chụp nhiều màn hình | `⌥⇧5` |
| Ảnh | Format | PNG |
| | Chất lượng JPG (chỉ hiện khi chọn JPG) | 90% |
| | Downscale Retina | Tắt |
| Lưu file | Thư mục lưu mặc định | `~/Pictures` |
| Hệ thống | Tự chạy khi đăng nhập | Bật |

- Thay đổi có hiệu lực ngay, không cần khởi động lại app.
- Ô đổi hotkey cho phép ghi phím mới và xóa hotkey.

## 7. Yêu cầu phi chức năng

1. **Tài nguyên khi chạy nền:** RAM thấp nhất có thể, CPU ~0% khi chờ hotkey.
2. **Tốc độ:** từ lúc bấm hotkey đến lúc overlay hiện, mục tiêu dưới 200 ms.
3. **Sau mỗi phiên chụp:** RAM quay về gần mức nền.
4. **Hiển thị:** overlay phủ lên cả menu bar, Dock và app đang full màn hình.
5. **Nhiều màn hình:** hoạt động đúng với các màn hình có tỉ lệ khác nhau (vd MacBook Retina + màn hình ngoài 1x); vùng chọn và ảnh xuất ra không bị lệch pixel.
6. **macOS hỗ trợ:** 26 và 27.

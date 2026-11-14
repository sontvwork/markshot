import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", initial: .init(.four, modifiers: [.option, .shift]))
    static let captureScreen = Self("captureScreen", initial: .init(.three, modifiers: [.option, .shift]))
    static let captureAllScreens = Self("captureAllScreens", initial: .init(.five, modifiers: [.option, .shift]))
}

/// Cài đặt lưu trong `UserDefaults`, dùng chung cho phần AppKit và `@AppStorage` của SwiftUI.
enum Prefs {
    enum Key {
        static let strokeColor = "strokeColor"
        static let strokeSize = "strokeSize"
    }

    private static let defaultColor = 0xFF3B30

    static var color: NSColor {
        get { NSColor(rgb: UserDefaults.standard.object(forKey: Key.strokeColor) as? Int ?? defaultColor) }
        set { UserDefaults.standard.set(newValue.rgb ?? defaultColor, forKey: Key.strokeColor) }
    }

    static var strokeSize: StrokeSize {
        get { (UserDefaults.standard.object(forKey: Key.strokeSize) as? Int).flatMap(StrokeSize.init) ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.strokeSize) }
    }
}

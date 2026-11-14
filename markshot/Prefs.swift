import AppKit
import KeyboardShortcuts
import UniformTypeIdentifiers

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", initial: .init(.four, modifiers: [.option, .shift]))
    static let captureScreen = Self("captureScreen", initial: .init(.three, modifiers: [.option, .shift]))
    static let captureAllScreens = Self("captureAllScreens", initial: .init(.five, modifiers: [.option, .shift]))
}

enum ImageFormat: String, CaseIterable {
    case png, jpg

    var title: String { rawValue.uppercased() }
    var contentType: UTType { self == .png ? .png : .jpeg }
}

/// Cài đặt lưu trong `UserDefaults`, dùng chung cho phần AppKit và `@AppStorage` của SwiftUI.
enum Prefs {
    enum Key {
        static let strokeColor = "strokeColor"
        static let strokeSize = "strokeSize"
        static let imageFormat = "imageFormat"
        static let jpgQuality = "jpgQuality"
        static let downscaleRetina = "downscaleRetina"
        static let saveDirectory = "saveDirectory"
        static let didSetupLoginItem = "didSetupLoginItem"
    }

    private static let defaultColor = 0xFF3B30
    static let defaultJPGQuality = 0.9
    static let defaultSaveDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory()

    private static var defaults: UserDefaults { .standard }

    static var color: NSColor {
        get { NSColor(rgb: defaults.object(forKey: Key.strokeColor) as? Int ?? defaultColor) }
        set { defaults.set(newValue.rgb ?? defaultColor, forKey: Key.strokeColor) }
    }

    static var strokeSize: StrokeSize {
        get { (defaults.object(forKey: Key.strokeSize) as? Int).flatMap(StrokeSize.init) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.strokeSize) }
    }

    static var imageFormat: ImageFormat {
        defaults.string(forKey: Key.imageFormat).flatMap(ImageFormat.init) ?? .png
    }

    static var jpgQuality: Double {
        defaults.object(forKey: Key.jpgQuality) as? Double ?? defaultJPGQuality
    }

    static var downscaleRetina: Bool {
        defaults.bool(forKey: Key.downscaleRetina)
    }

    static var saveDirectory: URL {
        URL(fileURLWithPath: defaults.string(forKey: Key.saveDirectory) ?? defaultSaveDirectory, isDirectory: true)
    }
}

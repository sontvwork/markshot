import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", initial: .init(.four, modifiers: [.option, .shift]))
    static let captureScreen = Self("captureScreen", initial: .init(.three, modifiers: [.option, .shift]))
    static let captureAllScreens = Self("captureAllScreens", initial: .init(.five, modifiers: [.option, .shift]))
}

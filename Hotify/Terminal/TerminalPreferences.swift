import Foundation

/// What the terminal remembers about how you like it, on this device: the text size, the theme, and how keys and
/// pastes behave. Plain defaults, read through `@AppStorage`, so Settings and an open terminal change together.
enum TerminalPreferences {
    static let fontSizeKey = "hotify.terminal.fontSize"
    static let themeKey = "hotify.terminal.theme"
    static let optionAsMetaKey = "hotify.terminal.optionAsMeta"
    static let confirmsPasteKey = "hotify.terminal.confirmsPaste"

    static let defaultFontSize: Double = 13
    static let fontSizes: ClosedRange<Double> = 9...24
    static let fontStep: Double = 1

    /// A size inside the range the canvas can draw well.
    static func clamp(_ size: Double) -> Double {
        min(max(size.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }
}

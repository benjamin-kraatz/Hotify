import SwiftUI

extension Font {
    /// Wide, heavy SF for names that head a screen. Hotify's one typographic voice; everything else is plain SF.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, weight: .heavy).width(.expanded)
    }
}

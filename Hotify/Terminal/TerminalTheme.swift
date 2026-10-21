import SwiftUI

/// Which look the terminal draws with.
enum TerminalTheme: String, CaseIterable, Identifiable {
    /// Hotify's own: a warm dark canvas, or a warm light one when the app is light.
    case ember
    /// Hotify's warm dark canvas, whatever the app's appearance.
    case emberDark
    /// The classic xterm colors on a plain black or white canvas.
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ember: "Ember"
        case .emberDark: "Ember, always dark"
        case .plain: "Plain"
        }
    }

    /// The colors for the app's appearance.
    func palette(for scheme: ColorScheme) -> TerminalPalette {
        switch (self, scheme) {
        case (.ember, .light): .emberLight
        case (.ember, _), (.emberDark, _): .emberDark
        case (.plain, .light): .plainLight
        case (.plain, _): .plainDark
        }
    }
}

/// A look for the terminal: the canvas, its text, the cursor, the selection, and the sixteen ANSI colors.
///
/// Colors are `0xRRGGBB`, since the same values feed SwiftTerm's palette, the platform's colors for the view,
/// and SwiftUI's for the chrome around it.
struct TerminalPalette: Equatable {
    var background: UInt32
    var foreground: UInt32
    var cursor: UInt32
    var cursorText: UInt32
    var selection: UInt32
    var selectedText: UInt32
    /// Black, red, green, yellow, blue, magenta, cyan, white, then their bright forms.
    var ansi: [UInt32]
    var isDark: Bool

    /// Hotify's dark canvas: charcoal with a little warmth, the brand red for errors and the cursor, the brand
    /// amber for yellow, and the preview blue for blue.
    static let emberDark = TerminalPalette(
        background: 0x15_1110,
        foreground: 0xED_E6DF,
        cursor: 0xFF_4D36,
        cursorText: 0xFF_FFFF,
        selection: 0x5C_2A21,
        selectedText: 0xFF_F4EE,
        ansi: [
            0x2A_221E, 0xFF_5A47, 0x7B_C98B, 0xFF_B020, 0x6B_9CFF, 0xD9_8AE0, 0x5F_CFD6, 0xD9_D0C8,
            0x6E_645E, 0xFF_7D6B, 0x9B_E0A8, 0xFF_C75A, 0x9B_BBFF, 0xEB_A8F0, 0x86_E4EA, 0xF7_F1EA,
        ],
        isDark: true
    )

    /// The same hues on warm paper, each one deepened enough to read on it.
    static let emberLight = TerminalPalette(
        background: 0xFB_F7F3,
        foreground: 0x2B_221E,
        cursor: 0xEE_3A1E,
        cursorText: 0xFF_FFFF,
        selection: 0xF6_CEC5,
        selectedText: 0x2B_221E,
        ansi: [
            0x2B_221E, 0xC9_341B, 0x2E_8B4E, 0xB8_6E00, 0x2C_5BE6, 0xA3_3FB5, 0x0F_8A94, 0xD6_CCC3,
            0x6E_645E, 0xEE_3A1E, 0x3D_A463, 0xD0_8200, 0x4F_79F0, 0xBF_5ED0, 0x1F_A3AD, 0xF2_EBE4,
        ],
        isDark: false
    )

    static let plainDark = TerminalPalette(
        background: 0x1E_1E1E,
        foreground: 0xE6_E6E6,
        cursor: 0xE6_E6E6,
        cursorText: 0x1E_1E1E,
        selection: 0x3A_4A5C,
        selectedText: 0xFF_FFFF,
        ansi: xterm,
        isDark: true
    )

    static let plainLight = TerminalPalette(
        background: 0xFF_FFFF,
        foreground: 0x00_0000,
        cursor: 0x00_0000,
        cursorText: 0xFF_FFFF,
        selection: 0xB4_D5FE,
        selectedText: 0x00_0000,
        ansi: xterm,
        isDark: false
    )

    /// xterm's sixteen, which most programs were tuned against.
    private static let xterm: [UInt32] = [
        0x00_0000, 0xCD_0000, 0x00_CD00, 0xCD_CD00, 0x00_00EE, 0xCD_00CD, 0x00_CDCD, 0xE5_E5E5,
        0x7F_7F7F, 0xFF_0000, 0x00_FF00, 0xFF_FF00, 0x5C_5CFF, 0xFF_00FF, 0x00_FFFF, 0xFF_FFFF,
    ]
}

extension Color {
    /// A color from `0xRRGGBB`.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        ForEach([TerminalPalette.emberDark, .emberLight, .plainDark, .plainLight], id: \.background) { palette in
            HStack(spacing: 4) {
                ForEach(palette.ansi, id: \.self) { value in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(rgb: value))
                        .frame(width: 22, height: 22)
                }
            }
            .padding(10)
            .background(Color(rgb: palette.background), in: .rect(cornerRadius: 8))
        }
    }
    .padding()
}

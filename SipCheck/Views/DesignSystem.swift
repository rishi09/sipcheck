import SwiftUI

// MARK: - Color Tokens

enum SipColors {
    static let background = Color(hex: "#1A1A1E")       // Near-black, main canvas
    static let surface = Color(hex: "#2A2A2E")           // Cards, elevated containers
    static let surfaceLight = Color(hex: "#F5F3F0")      // Light mode variant (forms)
    static let primary = Color(hex: "#4ECDC4")           // Teal. Buttons, tab active, links
    static let primaryDark = Color(hex: "#3BA99E")       // Pressed states
    static let textPrimary = Color(hex: "#F5F3F0")       // Cream. Main text on dark
    static let textSecondary = Color(hex: "#8E8E93")     // Gray. Metadata, timestamps
    static let starFilled = Color(hex: "#F1C40F")        // Gold. Filled stars
    static let starEmpty = Color(hex: "#3A3A3E")         // Dark gray. Empty stars
    static let wantToTry = Color(hex: "#4ECDC4")         // Teal (matches primary)
    static let destructive = Color(hex: "#E74C3C")       // Delete, sign out
    static let verdictTryIt = Color(hex: "#4CAF50")      // Green
    static let verdictSkipIt = Color(hex: "#E74C3C")     // Coral/rust
    static let verdictYourCall = Color(hex: "#F1C40F")   // Amber/gold
}

// MARK: - Typography

enum SipTypography {
    static let display = Font.system(size: 34, weight: .heavy)     // Verdict text ("Try It")
    static let title = Font.system(size: 24, weight: .bold)        // Screen titles
    static let headline = Font.system(size: 18, weight: .semibold) // Section headers
    static let body = Font.system(size: 16, weight: .regular)      // Descriptions
    static let subhead = Font.system(size: 14, weight: .medium)    // Metadata (ABV, style)
    static let caption = Font.system(size: 12, weight: .regular)   // Timestamps
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

struct DesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: Background Colors
                sectionHeader("Background Colors")
                HStack(spacing: 12) {
                    colorSwatch(SipColors.background, name: "background")
                    colorSwatch(SipColors.surface, name: "surface")
                    colorSwatch(SipColors.surfaceLight, name: "surfaceLight")
                }

                // MARK: Accent Colors
                sectionHeader("Accent Colors")
                HStack(spacing: 12) {
                    colorSwatch(SipColors.primary, name: "primary")
                    colorSwatch(SipColors.primaryDark, name: "primaryDark")
                    colorSwatch(SipColors.wantToTry, name: "wantToTry")
                    colorSwatch(SipColors.destructive, name: "destructive")
                }

                // MARK: Text Colors
                sectionHeader("Text Colors")
                HStack(spacing: 12) {
                    colorSwatch(SipColors.textPrimary, name: "textPrimary")
                    colorSwatch(SipColors.textSecondary, name: "textSecondary")
                }

                // MARK: Verdict Colors
                sectionHeader("Verdict Colors")
                HStack(spacing: 12) {
                    colorSwatch(SipColors.verdictTryIt, name: "verdictTryIt")
                    colorSwatch(SipColors.verdictSkipIt, name: "verdictSkipIt")
                    colorSwatch(SipColors.verdictYourCall, name: "verdictYourCall")
                }

                // MARK: Star Colors
                sectionHeader("Star Colors")
                HStack(spacing: 12) {
                    colorSwatch(SipColors.starFilled, name: "starFilled")
                    colorSwatch(SipColors.starEmpty, name: "starEmpty")
                }

                Divider()
                    .background(SipColors.textSecondary)

                // MARK: Typography
                sectionHeader("Typography")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display - Heavy 34pt")
                        .font(SipTypography.display)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Title - Bold 24pt")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Headline - Semibold 18pt")
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Body - Regular 16pt")
                        .font(SipTypography.body)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Subhead - Medium 14pt")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                    Text("Caption - Regular 12pt")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                }
            }
            .padding()
        }
        .background(SipColors.background)
        .previewDisplayName("Design System")
    }

    private static func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SipTypography.headline)
            .foregroundColor(SipColors.primary)
    }

    private static func colorSwatch(_ color: Color, name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SipColors.textSecondary.opacity(0.3), lineWidth: 1)
                )
            Text(name)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
    }
}

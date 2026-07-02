import SwiftUI

struct WantToTryCard: View {
    let scan: Scan
    var onTap: (() -> Void)?

    private var verdictStyle: VerdictStyle {
        VerdictStyle.style(for: scan.verdict)
    }

    /// "TRY IT" → "Try it" — sentence-cased for VoiceOver.
    private var spokenWord: String {
        let lower = verdictStyle.word.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// Up to two initials from the beer name, skipping filler words —
    /// "Pliny the Elder" → "PE".
    private var initials: String {
        let filler: Set<String> = ["the", "a", "an", "of", "de", "la", "le"]
        let words = scan.beerName
            .split(separator: " ")
            .map(String.init)
            .filter { !filler.contains($0.lowercased()) }
        return words.prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    /// Dark ink on pale SRM tiles (pilsner gold etc.), cream on dark ones —
    /// keeps the initials off the slop watchlist's white-on-gold trap.
    /// Single-sourced from the design system's SRM ink policy.
    private var tileTextColor: Color {
        StyleGradient.ink(for: scan.style).primary
    }

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: SipSpacing.xs) {
                // SRM mini-tile — a stout and a light lager look different.
                // Shared swatch: hairline keeps dark pours visible (crit #3).
                SRMSwatch(style: scan.style)
                    .frame(width: 100, height: 80)
                    .overlay(
                        ZStack {
                            Text(initials)
                                .font(SipTypography.title)
                                .foregroundColor(tileTextColor.opacity(0.85))
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    miniVerdictBadge
                                        .padding(SipSpacing.xs)
                                }
                            }
                        }
                    )

                // Beer name
                Text(scan.beerName)
                    .font(SipTypography.subhead)
                    .foregroundColor(SipColors.textPrimary)
                    .lineLimit(2)
                    .frame(width: 100, alignment: .leading)

                // Style
                if let style = scan.style {
                    Text(style)
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                        .lineLimit(1)
                        .frame(width: 100, alignment: .leading)
                }
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wantToTryCard_\(scan.id)")
        .accessibilityLabel("\(scan.beerName), \(spokenWord), want to try")
    }

    /// Compact triple-redundant badge: color + SF thumbs glyph + word,
    /// `.caption2` minimum (never 9pt), dark-on-amber via `VerdictStyle.textColor`.
    private var miniVerdictBadge: some View {
        HStack(spacing: SipSpacing.xs) {
            Image(systemName: verdictStyle.symbol)
            Text(verdictStyle.word)
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(verdictStyle.textColor)
        .padding(.horizontal, SipSpacing.s)
        .padding(.vertical, SipSpacing.xs)
        .background(Capsule().fill(verdictStyle.color))
    }
}

struct WantToTryCard_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: SipSpacing.m) {
            WantToTryCard(scan: Scan(
                beerName: "Pliny the Elder",
                style: "Imperial IPA",
                verdict: .tryIt,
                wantToTry: true
            ))
            WantToTryCard(scan: Scan(
                beerName: "Westvleteren 12",
                style: "Belgian Quad",
                verdict: .yourCall,
                wantToTry: true
            ))
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Want to Try Cards")
    }
}

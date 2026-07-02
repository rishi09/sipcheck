import SwiftUI

/// Triple-redundant verdict chip: color + SF thumbs glyph + word — never
/// color-only. All presentation comes from `VerdictStyle` (single source);
/// `style.textColor` is the white-on-gold fix (dark text on amber).
struct VerdictBadge: View {
    let verdict: Verdict

    private var style: VerdictStyle {
        VerdictStyle.style(for: verdict)
    }

    /// "TRY IT" → "Try it" — sentence-cased for VoiceOver.
    private var spokenWord: String {
        let lower = style.word.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    var body: some View {
        HStack(spacing: SipSpacing.xs) {
            Image(systemName: style.symbol)
                .font(.caption2.weight(.bold))
            Text(style.word)
                .font(SipTypography.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(style.textColor)
        .padding(.horizontal, SipSpacing.s)
        .padding(.vertical, SipSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                .fill(style.color)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verdict: \(spokenWord)")
    }
}

struct VerdictBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: SipSpacing.m) {
            VerdictBadge(verdict: .tryIt)
            VerdictBadge(verdict: .skipIt)
            VerdictBadge(verdict: .yourCall)
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Verdict Badges")
    }
}

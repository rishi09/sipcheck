import SwiftUI

// MARK: - Scan Vignette (onboarding page 2 illustration)
//
// Pure-SwiftUI animated vignette — no assets, no Lottie. A stylized phone
// rises toward a beer can on a shelf, a viewfinder pulses while a scan
// shimmer sweeps the label, then a TRY-IT thumb pops with a spring. Loops
// gently with a pause between cycles.
//
// Implementation notes:
// - iOS 17 only APIs: `keyframeAnimator(initialValue:trigger:)` runs ONE
//   choreographed timeline per trigger change; a `.task` loop bumps the
//   trigger once per cycle period. Between triggers the animator is idle,
//   and `.task` is cancelled on disappear → zero ongoing cost off-screen.
// - Reduce Motion: skips the animator and the task entirely and renders the
//   settled final frame (phone raised, green frame, thumb up).
// - Two intensity variants for the founder's in-app toggle:
//     .full    — phone + can + viewfinder/shimmer + thumb pop (V1)
//     .minimal — can + thumb pop only (V2)
// - Colors/typography come exclusively from DesignSystem tokens; the can is
//   the IPA amber StyleGradient, the thumb is verdictTry with textPrimary
//   ink (mirrors VerdictStyle for .tryIt).

enum ScanVignetteVariant: String, CaseIterable, Identifiable {
    case full       // V1: phone + can + scan shimmer + thumb pop
    case minimal    // V2: can + thumb pop only
    var id: String { rawValue }
}

// MARK: Stage geometry (shared by layout + keyframes)

private enum VignetteMetrics {
    static let stageWidth: CGFloat = 230
    static let stageHeight: CGFloat = 140   // hard cap from the design brief
    static let canWidth: CGFloat = 36
    static let canHeight: CGFloat = 78
    static let canOffsetX: CGFloat = -26    // can sits left of center…
    static let canOffsetY: CGFloat = -2
    static let phoneRise: CGFloat = 34      // …phone rises from bottom-right
}

// MARK: Animatable state (one struct = one keyframe timeline)

private struct VignetteState {
    var phoneOffsetY: CGFloat = VignetteMetrics.phoneRise
    var phoneOpacity: Double = 0
    var frameOpacity: Double = 0   // viewfinder brackets
    var framePulse: CGFloat = 1    // viewfinder breathing scale
    var frameTint: Double = 0      // 0 = accent teal → 1 = verdictTry green
    var shimmerY: CGFloat = -0.8   // normalized sweep position (-0.8…0.8)
    var shimmerOpacity: Double = 0
    var thumbScale: CGFloat = 0.01
    var thumbOpacity: Double = 0

    /// Idle pose between cycles: just the can on the shelf.
    static let rest = VignetteState()

    /// Reduce Motion pose: the final thumbs-up frame, frozen.
    static let settled = VignetteState(
        phoneOffsetY: 0, phoneOpacity: 1,
        frameOpacity: 1, framePulse: 1, frameTint: 1,
        shimmerY: 0.8, shimmerOpacity: 0,
        thumbScale: 1, thumbOpacity: 1
    )
}

// MARK: Per-variant choreography timing

private struct VignetteTiming {
    let riseLen: Double     // phone rise duration
    let scanStart: Double   // viewfinder in + shimmer sweep begins
    let scanLen: Double     // shimmer sweep duration
    let popAt: Double       // thumb spring begins
    let holdEnd: Double     // verdict hold ends, fade-out begins
    let fadeLen: Double     // fade-out duration
    let period: Double      // trigger interval = timeline + inter-cycle pause

    init(_ variant: ScanVignetteVariant) {
        switch variant {
        case .full:
            riseLen = 0.8; scanStart = 0.95; scanLen = 1.05
            popAt = 2.15; holdEnd = 3.35; fadeLen = 0.55
            period = 5.4    // ≈1.5s calm pause between cycles
        case .minimal:
            // Phone/viewfinder tracks still evaluate (never rendered) so all
            // durations stay > 0; only popAt/holdEnd shape what's visible.
            riseLen = 0.3; scanStart = 0.35; scanLen = 0.4
            popAt = 0.45; holdEnd = 2.5; fadeLen = 0.5
            period = 4.1
        }
    }
}

// MARK: - View

struct ScanVignetteView: View {
    var variant: ScanVignetteVariant = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cycle = 0

    private var timing: VignetteTiming { VignetteTiming(variant) }

    var body: some View {
        Group {
            if reduceMotion {
                // Frozen final frame — no animator, no task, no motion.
                composition(VignetteState.settled)
            } else {
                Color.clear
                    .keyframeAnimator(
                        initialValue: VignetteState.rest,
                        trigger: cycle
                    ) { base, state in
                        ZStack {
                            base
                            composition(state)
                        }
                    } keyframes: { _ in
                        // ---- Phone: rise in, hold, fade with the group ----
                        KeyframeTrack(\VignetteState.phoneOffsetY) {
                            MoveKeyframe(VignetteMetrics.phoneRise)
                            CubicKeyframe(0, duration: timing.riseLen)
                            LinearKeyframe(0, duration: timing.holdEnd + timing.fadeLen - timing.riseLen)
                        }
                        KeyframeTrack(\VignetteState.phoneOpacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(1, duration: 0.35)
                            LinearKeyframe(1, duration: timing.holdEnd - 0.35)
                            LinearKeyframe(0, duration: timing.fadeLen)
                        }
                        // ---- Viewfinder: appear, breathe while scanning ----
                        KeyframeTrack(\VignetteState.frameOpacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: timing.scanStart - 0.2)
                            LinearKeyframe(1, duration: 0.2)
                            LinearKeyframe(1, duration: timing.holdEnd - timing.scanStart)
                            LinearKeyframe(0, duration: timing.fadeLen)
                        }
                        KeyframeTrack(\VignetteState.framePulse) {
                            MoveKeyframe(1)
                            LinearKeyframe(1, duration: timing.scanStart)
                            CubicKeyframe(1.06, duration: timing.scanLen * 0.25)
                            CubicKeyframe(1.0, duration: timing.scanLen * 0.25)
                            CubicKeyframe(1.06, duration: timing.scanLen * 0.25)
                            CubicKeyframe(1.0, duration: timing.scanLen * 0.25)
                        }
                        // Teal → verdict-green flash the moment the scan lands.
                        KeyframeTrack(\VignetteState.frameTint) {
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: timing.scanStart + timing.scanLen)
                            LinearKeyframe(1, duration: 0.2)
                        }
                        // ---- Scan shimmer: one sweep down the label ----
                        KeyframeTrack(\VignetteState.shimmerY) {
                            MoveKeyframe(-0.8)
                            LinearKeyframe(-0.8, duration: timing.scanStart)
                            CubicKeyframe(0.8, duration: timing.scanLen)
                        }
                        KeyframeTrack(\VignetteState.shimmerOpacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: timing.scanStart)
                            LinearKeyframe(0.9, duration: timing.scanLen * 0.2)
                            LinearKeyframe(0.9, duration: timing.scanLen * 0.6)
                            LinearKeyframe(0, duration: timing.scanLen * 0.2)
                        }
                        // ---- Verdict thumb: spring pop, hold, fade ----
                        KeyframeTrack(\VignetteState.thumbScale) {
                            MoveKeyframe(0.01)
                            LinearKeyframe(0.01, duration: timing.popAt)
                            SpringKeyframe(1.0, duration: 0.6,
                                           spring: Spring(duration: 0.35, bounce: 0.45))
                            LinearKeyframe(1.0, duration: timing.holdEnd + timing.fadeLen - timing.popAt - 0.6)
                        }
                        KeyframeTrack(\VignetteState.thumbOpacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: timing.popAt)
                            LinearKeyframe(1, duration: 0.12)
                            LinearKeyframe(1, duration: timing.holdEnd - timing.popAt - 0.12)
                            LinearKeyframe(0, duration: timing.fadeLen)
                        }
                    }
            }
        }
        .frame(width: VignetteMetrics.stageWidth, height: VignetteMetrics.stageHeight)
        .accessibilityHidden(true)   // decorative; the page title/copy carry meaning
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            cycle &+= 1   // kick off the first cycle immediately on appear
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(timing.period * 1_000_000_000))
                if Task.isCancelled { break }
                cycle &+= 1
            }
        }
    }

    // MARK: Composition (pure function of animatable state)

    @ViewBuilder
    private func composition(_ state: VignetteState) -> some View {
        ZStack {
            shelf
            canView(state)
            if variant == .full {
                viewfinder(state)
                phone(state)
            }
            thumb(state)
        }
    }

    private var shelf: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(SipColors.surfaceElevated)
            .frame(width: 120, height: 4)
            .offset(x: VignetteMetrics.canOffsetX,
                    y: VignetteMetrics.canOffsetY + VignetteMetrics.canHeight / 2 + 2)
    }

    /// Amber IPA can: SRM gradient body, cream label band, lid hint, and the
    /// scan shimmer clipped inside. Hairline stroke per SRMSwatch house rule.
    private func canView(_ state: VignetteState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return ZStack {
            shape.fill(StyleGradient.gradient(for: "IPA"))
            // Lid hint
            VStack {
                Capsule()
                    .fill(SipColors.textPrimary.opacity(0.35))
                    .frame(width: VignetteMetrics.canWidth - 10, height: 3)
                    .padding(.top, 4)
                Spacer()
            }
            // Label band with a tiny motif — reads "beer label" without assets
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(SipColors.textPrimary.opacity(0.92))
                .frame(width: VignetteMetrics.canWidth - 10, height: 24)
                .overlay(
                    Circle()
                        .fill(SipColors.srmInk.opacity(0.85))
                        .frame(width: 7, height: 7)
                )
            // Scan shimmer sweeping the label (full variant only). Cream
            // textPrimary token, not literal white — .plusLighter lifts it
            // to the same white-hot sweep while staying on-palette.
            if variant == .full {
                LinearGradient(
                    colors: [.clear, SipColors.textPrimary.opacity(0.6), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 30)
                .offset(y: state.shimmerY * (VignetteMetrics.canHeight / 2 + 15))
                .opacity(state.shimmerOpacity)
                .blendMode(.plusLighter)
            }
        }
        .frame(width: VignetteMetrics.canWidth, height: VignetteMetrics.canHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .offset(x: VignetteMetrics.canOffsetX, y: VignetteMetrics.canOffsetY)
    }

    /// Viewfinder brackets around the can. Two stacked tints crossfade
    /// accent → verdictTry (Color can't be keyframed directly).
    private func viewfinder(_ state: VignetteState) -> some View {
        ZStack {
            Image(systemName: "viewfinder")
                .font(.system(size: 96, weight: .ultraLight))
                .foregroundColor(SipColors.accent)
                .opacity(1 - state.frameTint)
            Image(systemName: "viewfinder")
                .font(.system(size: 96, weight: .ultraLight))
                .foregroundColor(SipColors.verdictTry)
                .opacity(state.frameTint)
        }
        .scaleEffect(state.framePulse)
        .opacity(state.frameOpacity)
        .offset(x: VignetteMetrics.canOffsetX, y: VignetteMetrics.canOffsetY)
    }

    /// Stylized phone rising from bottom-right toward the can.
    private func phone(_ state: VignetteState) -> some View {
        Image(systemName: "iphone")
            .font(.system(size: 54, weight: .regular))
            .foregroundColor(SipColors.textPrimary)
            .rotationEffect(.degrees(-10))
            .offset(x: 56, y: 22 + state.phoneOffsetY)
            .opacity(state.phoneOpacity)
    }

    /// The payoff: TRY-IT thumb popping at the can's top-right. Mirrors
    /// VerdictStyle(.tryIt): verdictTry fill, textPrimary symbol.
    private func thumb(_ state: VignetteState) -> some View {
        ZStack {
            Circle().fill(SipColors.verdictTry)
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(SipColors.textPrimary)
        }
        .frame(width: 44, height: 44)
        .scaleEffect(state.thumbScale)
        .opacity(state.thumbOpacity)
        .offset(x: VignetteMetrics.canOffsetX + 44,
                y: VignetteMetrics.canOffsetY - 40)
    }
}

// MARK: - Preview

struct ScanVignette_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: SipSpacing.xxl) {
            VStack(spacing: SipSpacing.s) {
                ScanVignetteView(variant: .full)
                Text("V1 — full vignette")
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
            }
            VStack(spacing: SipSpacing.s) {
                ScanVignetteView(variant: .minimal)
                Text("V2 — minimal")
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SipColors.background)
        .preferredColorScheme(.dark)
        .previewDisplayName("Scan Vignette")
    }
}

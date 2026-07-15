import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject var drinkStore: DrinkStore
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var scanStore: ScanStore

    @State private var showingSettings = false

    private var personaLabel: String {
        // Read via TastePreferences (KVS-first) so the badge matches what the
        // verdict engine actually uses — raw UserDefaults could disagree.
        let prefs = TastePreferences.current
        let vibe = prefs.vibe
        let adventure = prefs.adventure
        switch vibe {
        case "Hoppy & Bitter": return "Hop Head"
        case "Dark & Roasty": return "Dark Arts"
        case "Crisp & Light": return "Easy Drinker"
        case "Fruity & Easy": return "Flavor Chaser"
        case "Sour & Weird":
            return adventure == "Give Me the Weird Stuff" ? "Chaos Sipper" : "Sour Seeker"
        default: return "Explorer"
        }
    }

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SipSpacing.xl) {
                    // MARK: - Header
                    headerSection

                    // MARK: - Persona Badge
                    personaBadge

                    // MARK: - Stats Row
                    statsRow

                    Divider()
                        .background(SipColors.textSecondary.opacity(0.3))
                        .padding(.horizontal)

                    // MARK: - Top Styles
                    topStylesSection

                    Divider()
                        .background(SipColors.textSecondary.opacity(0.3))
                        .padding(.horizontal)

                    // MARK: - Recent Scans
                    recentScansSection

                    // Tab-bar clearance is inherited from MainTabView's shared
                    // .sipTabBarClearance() safe-area contract — no magic padding.
                }
                .padding(.top, SipSpacing.l)
            }
            .compatScrollEdgeSoft()
        }
        // .contain keeps this container id from clobbering every child's
        // identifier (a bare container identifier overwrites them all).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profileTab")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Spacer()

            Text("My Profile")
                .font(SipTypography.title)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityIdentifier("profileTitle")

            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
            .padding(.trailing, SipSpacing.m)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsTabView()
                .environmentObject(drinkStore)
                .environmentObject(scanStore)
                .environmentObject(journalStore)
        }
    }

    // MARK: - Persona Badge

    // Inverted treatment (dark fill + teal text): the badge is a status label,
    // not a tappable — solid teal fills stay reserved for actionable controls.
    private var personaBadge: some View {
        HStack(spacing: SipSpacing.s) {
            Image(systemName: "mug.fill")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.accent)

            Text(personaLabel)
                .font(SipTypography.headline)
                .foregroundColor(SipColors.accent)
        }
        .padding(.horizontal, SipSpacing.xl)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(SipColors.surfaceElevated)
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: SipSpacing.l) {
            statBox(
                value: journalStore.entries.count,
                label: "Beers Logged",
                accessibilityId: "beersLoggedCount"
            )

            statBox(
                value: journalStore.lovedEntries.count,
                label: "Loved",
                accessibilityId: "lovedCount"
            )
        }
        .padding(.horizontal, 20)
    }

    // Stat cards: elevated gray + heavy off-white numerals — keep this treatment.
    private func statBox(value: Int, label: String, accessibilityId: String) -> some View {
        VStack(spacing: SipSpacing.xs) {
            Text("\(value)")
                .font(SipTypography.numberHero)
                .fontWidth(.compressed)
                .monospacedDigit()
                .foregroundColor(SipColors.textPrimary)
                .accessibilityIdentifier(accessibilityId)

            Text(label)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SipSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                .fill(SipColors.surface)
        )
    }

    // MARK: - Top Styles

    private var topStylesSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            Text("Top Styles")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .padding(.horizontal, 20)

            if styleDistribution.isEmpty {
                Text("Log some beers to see your top styles")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: SipSpacing.s) {
                    ForEach(styleDistribution, id: \.style) { item in
                        // Shared component; maxPercentage defaults to the
                        // absolute 100% basis, so bar widths actually encode
                        // the printed percentages.
                        StyleBarView(style: item.style, percentage: item.percentage)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .accessibilityIdentifier("topStyles")
    }

    private var styleDistribution: [(style: String, percentage: Double)] {
        let entries = journalStore.entries
        guard !entries.isEmpty else { return [] }

        // Group by style
        var styleCounts: [String: Int] = [:]
        for entry in entries {
            let style = entry.style.isEmpty ? "Unknown" : entry.style
            styleCounts[style, default: 0] += 1
        }

        let total = Double(entries.count)

        // Sort by count descending
        let sorted = styleCounts.sorted { $0.value > $1.value }

        // Take top 4, rest as "Other"
        var result: [(style: String, percentage: Double)] = []
        for (index, item) in sorted.enumerated() {
            if index < 4 {
                result.append((style: item.key, percentage: (Double(item.value) / total) * 100))
            }
        }

        // Aggregate "Other" if there are more than 4 styles
        if sorted.count > 4 {
            let otherCount = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
            result.append((style: "Other", percentage: (Double(otherCount) / total) * 100))
        }

        return result
    }

    // MARK: - Recent Scans

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            Text("Recent Scans")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .padding(.horizontal, 20)

            if scanStore.recentScans.isEmpty {
                Text("Scan a beer to see it here")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(scanStore.recentScans) { scan in
                        scanRow(scan)

                        if scan.id != scanStore.recentScans.last?.id {
                            Divider()
                                .background(SipColors.textSecondary.opacity(0.2))
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("recentScans")
    }

    // Rows stay non-tappable for now — revisitable scans is future work.
    private func scanRow(_ scan: Scan) -> some View {
        HStack(spacing: SipSpacing.m) {
            // SRM mini-tile when we know the style; verdict-colored dot otherwise.
            if let style = scan.style, !style.isEmpty {
                SRMSwatch(style: style, cornerRadius: SipRadius.badge)
                    .frame(width: 36, height: 36)
            } else {
                Circle()
                    .fill(VerdictStyle.style(for: scan.verdict).color)
                    .frame(width: 8, height: 8)
                    .frame(width: 36, height: 36)
            }

            // Beer name
            Text(scan.beerName)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textPrimary)

            Spacer()

            // Verdict badge
            VerdictBadge(verdict: scan.verdict)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct ProfileTabView_Previews: PreviewProvider {
    static var previews: some View {
        let journalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_journal_\(UUID().uuidString)")
        let scanDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_scan_\(UUID().uuidString)")

        try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)

        let journalStore = JournalStore(storageDirectory: journalDir, useSeedData: true)
        let scanStore = ScanStore(storageDirectory: scanDir, useSeedData: true)

        return ProfileTabView()
            .environmentObject(DrinkStore())
            .environmentObject(journalStore)
            .environmentObject(scanStore)
            .previewDisplayName("Profile Tab")
    }
}

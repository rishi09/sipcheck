import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject var drinkStore: DrinkStore
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var scanStore: ScanStore

    @State private var showingSettings = false

    private var personaLabel: String {
        let vibe = UserDefaults.standard.string(forKey: "tasteVibe") ?? ""
        let adventure = UserDefaults.standard.string(forKey: "tasteAdventure") ?? ""
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
                VStack(spacing: 24) {
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

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
        }
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
                    .font(.system(size: 20))
                    .foregroundColor(SipColors.textPrimary)
            }
            .padding(.trailing, 20)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsTabView()
                .environmentObject(drinkStore)
                .environmentObject(scanStore)
                .environmentObject(journalStore)
        }
    }

    // MARK: - Persona Badge

    private var personaBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18))
                .foregroundColor(SipColors.background)

            Text(personaLabel)
                .font(SipTypography.headline)
                .foregroundColor(SipColors.background)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(SipColors.primary)
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
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

    private func statBox(value: Int, label: String, accessibilityId: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(SipTypography.display)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityIdentifier(accessibilityId)

            Text(label)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SipColors.surface)
        )
    }

    // MARK: - Top Styles

    private var topStylesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 8) {
                    ForEach(styleDistribution, id: \.style) { item in
                        StyleBarView(
                            style: item.style,
                            percentage: item.percentage,
                            maxPercentage: styleDistribution.first?.percentage ?? 100
                        )
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
        VStack(alignment: .leading, spacing: 12) {
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

    private func scanRow(_ scan: Scan) -> some View {
        HStack(spacing: 12) {
            // Beer icon placeholder
            Image(systemName: "mug.fill")
                .font(.system(size: 24))
                .foregroundColor(SipColors.primary)
                .frame(width: 36, height: 36)

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

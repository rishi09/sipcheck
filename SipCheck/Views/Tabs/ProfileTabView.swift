import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject var drinkStore: DrinkStore
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var scanStore: ScanStore

    @State private var showingSettings = false
    @State private var selectedScan: RecentScanSelection?

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
        .sheet(item: $selectedScan) { selection in
            RecentScanDetailView(
                scanID: selection.id,
                fallbackScan: selection.snapshot
            )
            .environmentObject(drinkStore)
            .environmentObject(journalStore)
            .environmentObject(scanStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentScans")
    }

    private func scanRow(_ scan: Scan) -> some View {
        Button {
            selectedScan = RecentScanSelection(snapshot: scan)
        } label: {
            HStack(spacing: SipSpacing.m) {
                StoredPhotoView(fileName: scan.photoFileName) {
                    SRMSwatch(style: scan.style, cornerRadius: SipRadius.badge)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous))

                VStack(alignment: .leading, spacing: SipSpacing.xs) {
                    Text(scan.beerName)
                        .font(SipTypography.body)
                        .fontWeight(.medium)
                        .foregroundColor(SipColors.textPrimary)
                        .lineLimit(2)

                    Text(scanRowMetadata(scan))
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VerdictBadge(verdict: scan.verdict)
                    .fixedSize(horizontal: true, vertical: false)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SipColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, SipSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scanRowAccessibilityLabel(scan))
        .accessibilityHint("Opens scan details")
        .accessibilityIdentifier("recentScanRow_\(scan.id.uuidString)")
    }

    private func scanRowMetadata(_ scan: Scan) -> String {
        var parts: [String] = []
        if let style = scan.style?.trimmingCharacters(in: .whitespacesAndNewlines), !style.isEmpty {
            parts.append(style)
        }
        parts.append(scan.timestamp.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " \u{00B7} ")
    }

    private func scanRowAccessibilityLabel(_ scan: Scan) -> String {
        let verdict = VerdictStyle.style(for: scan.verdict).word.lowercased()
        return "\(scan.beerName), \(verdict), \(scanRowMetadata(scan))"
    }

}

private struct RecentScanSelection: Identifiable {
    let snapshot: Scan
    var id: UUID { snapshot.id }
}

private struct RecentScanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var journalStore: JournalStore
    @EnvironmentObject private var scanStore: ScanStore

    let scanID: UUID
    let fallbackScan: Scan

    /// Photo compression and enrichment intentionally finish after the verdict
    /// appears. Resolve through the observable store so an already-open sheet
    /// picks up those late fields instead of freezing the tapped row's copy.
    private var scan: Scan {
        scanStore.scans.first(where: { $0.id == scanID }) ?? fallbackScan
    }

    private var linkedJournalEntry: JournalEntry? {
        if let linkedJournalId = scan.linkedJournalId,
           let linked = journalStore.entries.first(where: { $0.id == linkedJournalId }) {
            return linked
        }
        return journalStore.entries.first(where: { $0.linkedScanId == scan.id })
    }

    private var explanation: String {
        let trimmed = scan.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No explanation was saved for this scan." : trimmed
    }

    private var formattedScanDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: scan.timestamp)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SipColors.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SipSpacing.xl) {
                        scanHeader

                        Divider()
                            .background(SipColors.textSecondary.opacity(0.25))

                        explanationSection

                        Divider()
                            .background(SipColors.textSecondary.opacity(0.25))

                        detailsSection

                        if let origin = nonEmpty(scan.origin) {
                            Divider()
                                .background(SipColors.textSecondary.opacity(0.25))

                            detailSection(title: "About this beer", text: origin)
                                .accessibilityIdentifier("recentScanDetailOrigin")
                        }

                        if let entry = linkedJournalEntry {
                            Divider()
                                .background(SipColors.textSecondary.opacity(0.25))

                            journalSection(entry)
                        }
                    }
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.bottom, SipSpacing.xxl)
                }
            }
            .navigationTitle("Scan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close scan details")
                    .accessibilityIdentifier("recentScanDetailClose")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentScanDetail")
    }

    private var scanHeader: some View {
        VStack(spacing: SipSpacing.m) {
            StoredPhotoView(fileName: scan.photoFileName) {
                SRMSwatch(style: scan.style, cornerRadius: SipRadius.badge)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .clipShape(RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                    .strokeBorder(SipColors.textSecondary.opacity(0.25), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                scan.photoFileName == nil
                    ? "Beer style placeholder for \(scan.beerName)"
                    : "Captured photo of \(scan.beerName)"
            )
            .accessibilityIdentifier("recentScanDetailPhoto")

            VStack(spacing: SipSpacing.xs) {
                Text(scan.beerName)
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recentScanDetailBeerName")

                if let brand = nonEmpty(scan.brand), brand != scan.beerName {
                    Text(brand)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("recentScanDetailBrand")
                }
            }

            VerdictBadge(verdict: scan.verdict)
                .accessibilityIdentifier("recentScanDetailVerdict")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SipSpacing.s)
    }

    private var explanationSection: some View {
        detailSection(title: "Why this verdict", text: explanation)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Why this verdict. \(explanation)")
            .accessibilityIdentifier("recentScanDetailExplanation")
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            Text("Details")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)

            if let brand = nonEmpty(scan.brand), brand != scan.beerName {
                detailRow(label: "Brewery", value: brand, accessibilityID: "recentScanDetailBrewery")
            }

            if let style = nonEmpty(scan.style) {
                detailRow(label: "Style", value: style, accessibilityID: "recentScanDetailStyle")
            }

            if let abv = scan.abv {
                detailRow(
                    label: "ABV",
                    value: String(format: "%.1f%%", abv),
                    accessibilityID: "recentScanDetailABV"
                )
            }

            detailRow(
                label: "Scanned",
                value: formattedScanDate,
                accessibilityID: "recentScanDetailDate"
            )

            if linkedJournalEntry != nil {
                detailRow(label: "Status", value: "Logged", accessibilityID: "recentScanDetailStatus")
            } else if scan.wantToTry {
                detailRow(label: "Status", value: "Saved for later", accessibilityID: "recentScanDetailStatus")
            }
        }
        .accessibilityIdentifier("recentScanDetailMetadata")
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: SipSpacing.s) {
            Text(title)
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)

            Text(text)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(label: String, value: String, accessibilityID: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SipSpacing.l) {
            Text(label)
                .font(SipTypography.subhead)
                .foregroundColor(SipColors.textSecondary)

            Spacer(minLength: SipSpacing.m)

            Text(value)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityIdentifier(accessibilityID)
    }

    private func journalSection(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            HStack(spacing: SipSpacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(SipColors.accent)

                Text("Logged in Journal")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
            }

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= entry.rating ? "star.fill" : "star")
                        .font(SipTypography.body)
                        .foregroundColor(star <= entry.rating ? SipColors.starFilled : SipColors.starEmpty)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(entry.rating) of 5 stars")

            Text("Logged \(entry.dateLogged.formatted(date: .long, time: .omitted))")
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)

            if let notes = nonEmpty(entry.notes) {
                Text(notes)
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SipSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                .fill(SipColors.surfaceElevated)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentScanDetailJournalContext")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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

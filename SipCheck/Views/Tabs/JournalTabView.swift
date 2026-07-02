import SwiftUI

enum JournalFilter: String, CaseIterable {
    case all = "All"
    case loved = "Loved"
    case ok = "OK"
    case notForMe = "Not For Me"
}

struct JournalTabView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var drinkStore: DrinkStore
    @State private var searchText = ""
    @State private var selectedFilter: JournalFilter = .all
    @State private var selectedWantToTryScan: Scan?
    @State private var showingAddBeer = false
    @State private var selectedEntry: JournalEntry?

    private var filteredEntries: [JournalEntry] {
        var result = journalStore.entries

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.beerName.localizedCaseInsensitiveContains(searchText) ||
                $0.brand.localizedCaseInsensitiveContains(searchText) ||
                $0.style.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply rating filter
        switch selectedFilter {
        case .all:
            break
        case .loved:
            result = result.filter { $0.rating >= 4 }
        case .ok:
            result = result.filter { $0.rating == 3 }
        case .notForMe:
            result = result.filter { $0.rating <= 2 }
        }

        return result
    }

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text("My Beers")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                        .padding(.horizontal, SipSpacing.l)
                        .padding(.top, SipSpacing.s)

                    // Search bar
                    searchBar

                    // Filter chips
                    filterChips

                    // Want to Try section
                    if !scanStore.wantToTryScans.isEmpty {
                        wantToTrySection
                    }

                    // Tried section
                    triedSection
                }
                // Tab-bar clearance is inherited from MainTabView's shared
                // .sipTabBarClearance() safe-area contract — no magic padding.
            }
            .compatScrollEdgeSoft()
        }
        // .contain keeps this container id from clobbering every child's
        // identifier (a bare container identifier overwrites them all).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journalTab")
        .sheet(item: $selectedEntry) { entry in
            JournalEntryDetailView(entry: entry, linkedVerdict: linkedVerdict(for: entry))
                .environmentObject(journalStore)
        }
        .sheet(isPresented: $showingAddBeer) {
            if let scan = selectedWantToTryScan {
                AddBeerView(prefill: AddBeerPrefill(
                    name: scan.beerName,
                    style: scan.style ?? BeerStyle.other.rawValue,
                    abv: scan.abv,
                    scanId: scan.id
                ))
                .environmentObject(drinkStore)
                .environmentObject(journalStore)
                .environmentObject(scanStore)
            }
        }
    }

    // MARK: - Scan linkage (display-only lookup for the detail sheet's loop-closer line)

    private func linkedVerdict(for entry: JournalEntry) -> Verdict? {
        if let scanId = entry.linkedScanId,
           let verdict = scanStore.scans.first(where: { $0.id == scanId })?.verdict {
            return verdict
        }
        // Manual logs carry no linkedScanId — fall back to an exact-name hit
        // in scan history. Same trust bar as the verdict card's "you've had
        // this one" banner: exact match only, never fuzzy.
        let name = entry.beerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return scanStore.scans.first(where: {
            $0.beerName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })?.verdict
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: SipSpacing.s) {
            Image(systemName: "magnifyingglass")
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)

            TextField("Search your beers...", text: $searchText)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityIdentifier("journalSearch")
        }
        .padding(SipSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                .fill(SipColors.surface)
        )
        .padding(.horizontal, SipSpacing.l)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SipSpacing.s) {
                ForEach(JournalFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, SipSpacing.l)
        }
    }

    private func filterChip(_ filter: JournalFilter) -> some View {
        Button(filter.rawValue) {
            selectedFilter = filter
        }
        .buttonStyle(SipChipStyle(isSelected: selectedFilter == filter))
        .accessibilityIdentifier(accessibilityId(for: filter))
    }

    private func accessibilityId(for filter: JournalFilter) -> String {
        switch filter {
        case .all: return "filterAll"
        case .loved: return "filterLoved"
        case .ok: return "filterOK"
        case .notForMe: return "filterNotForMe"
        }
    }

    // MARK: - Want to Try Section

    private var wantToTrySection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            // Section headers are metadata, not titles (teal is reserved for tappable things).
            Text("Want to Try")
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
                .padding(.horizontal, SipSpacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SipSpacing.m) {
                    ForEach(scanStore.wantToTryScans) { scan in
                        WantToTryCard(scan: scan) {
                            selectedWantToTryScan = scan
                            showingAddBeer = true
                        }
                    }
                }
                .padding(.horizontal, SipSpacing.l)
            }
        }
    }

    // MARK: - Tried Section

    private var triedSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.s) {
            Text("Tried \u{00B7} \(filteredEntries.count) \(filteredEntries.count == 1 ? "beer" : "beers")")
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
                .padding(.horizontal, SipSpacing.l)

            if filteredEntries.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            JournalEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if journalStore.entries.isEmpty {
                // Truly no data yet
                ContentUnavailableView(
                    "Nothing logged yet — scan a beer to start",
                    systemImage: "book"
                )
            } else {
                // Data exists but the search/filter excludes it all
                ContentUnavailableView(
                    "No beers match",
                    systemImage: "magnifyingglass"
                )
            }
        }
        .foregroundColor(SipColors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SipSpacing.xl)
    }
}

struct JournalTabView_Previews: PreviewProvider {
    static var previews: some View {
        let journalStore = JournalStore(
            storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-journal"),
            useSeedData: true
        )
        let scanStore = ScanStore(
            storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-scans"),
            useSeedData: true
        )

        JournalTabView()
            .environmentObject(journalStore)
            .environmentObject(scanStore)
            .environmentObject(DrinkStore())
            .previewDisplayName("Journal Tab")
    }
}

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
    @State private var selectedEntry: JournalEntry?
    @State private var selectedLegacyDrink: Drink?

    private var librarySnapshot: BeerLibrarySnapshot {
        BeerLibrarySnapshot(
            journalRecords: journalStore.syncRecords,
            legacyDrinks: drinkStore.drinks,
            scans: scanStore.scans
        )
    }

    private var projectedSavedScans: [Scan] {
        librarySnapshot.savedItems.compactMap { $0.savedScans.first }
    }

    private var filteredRecords: [BeerTasteRecord] {
        var result = librarySnapshot.tasteRecords

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.brewery.localizedCaseInsensitiveContains(searchText) ||
                $0.style.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply rating filter
        switch selectedFilter {
        case .all:
            break
        case .loved:
            result = result.filter { $0.rating == .like }
        case .ok:
            result = result.filter { $0.rating == .neutral }
        case .notForMe:
            result = result.filter { $0.rating == .dislike }
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
                    if !projectedSavedScans.isEmpty {
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
            JournalEntryDetailView(
                entry: entry,
                linkedVerdict: linkedVerdict(for: entry),
                linkedFactSource: linkedFactSource(for: entry)
            )
                .environmentObject(journalStore)
                .environmentObject(drinkStore)
        }
        .sheet(item: $selectedLegacyDrink) { drink in
            JournalEntryDetailView(
                entry: displayEntry(for: BeerTasteRecord(legacyDrink: drink)),
                deleteButtonTitle: "Delete from history",
                onSave: { rating, notes in
                    migrateLegacyDrink(drink, rating: rating, notes: notes)
                },
                onDelete: {
                    drinkStore.deleteDrink(drink)
                }
            )
            .environmentObject(journalStore)
            .environmentObject(drinkStore)
        }
        // item-driven, not isPresented + if-let: the two-state write raced the
        // sheet's first render and presented a completely BLANK sheet (founder
        // bug video 2026-07-07). sheet(item:) can't render without its scan.
        .sheet(item: $selectedWantToTryScan) { scan in
            AddBeerView(prefill: AddBeerPrefill(
                name: scan.beerName,
                brand: scan.brand ?? "",
                style: scan.style ?? BeerStyle.other.rawValue,
                abv: scan.abv,
                photoFileName: scan.photoFileName,
                scanId: scan.id,
                factSource: scan.factSource
            ))
            .environmentObject(drinkStore)
            .environmentObject(journalStore)
            .environmentObject(scanStore)
        }
    }

    // MARK: - Scan linkage (display-only lookup for the detail sheet's loop-closer line)

    private func linkedVerdict(for entry: JournalEntry) -> Verdict? {
        // "We said…" is a past-tense personal claim, so only an explicit scan
        // relationship is sufficient. Same-name fallbacks can borrow a verdict
        // from another brewery and are intentionally omitted.
        linkedScan(for: entry)?.verdict
    }

    /// Attribution must use the explicit scan relationship; a name-only match
    /// could attach the wrong brewery page to a different beer.
    private func linkedFactSource(for entry: JournalEntry) -> BeerFactSource? {
        linkedScan(for: entry)?.factSource
    }

    private func linkedScan(for entry: JournalEntry) -> Scan? {
        let candidate: Scan?
        if let scanId = entry.linkedScanId {
            candidate = scanStore.scans.first(where: { $0.id == scanId })
        } else {
            // Older records may have persisted only the reverse relationship.
            candidate = scanStore.scans.first(where: { $0.linkedJournalId == entry.id })
        }
        guard let candidate,
              BeerLibraryIdentity.explicitLinkMatches(
                scanName: candidate.beerName,
                scanBrewery: candidate.brand,
                journalName: entry.beerName,
                journalBrewery: entry.brand
              ) else { return nil }
        return candidate
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
                    ForEach(projectedSavedScans) { scan in
                        WantToTryCard(scan: scan) {
                            selectedWantToTryScan = scan
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
            Text("Tried \u{00B7} \(filteredRecords.count) \(filteredRecords.count == 1 ? "log" : "logs")")
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
                .padding(.horizontal, SipSpacing.l)

            if filteredRecords.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRecords) { record in
                        Button {
                            switch record.source {
                            case .journal:
                                selectedEntry = journalStore.entries.first { $0.id == record.id }
                            case .legacyDrink:
                                selectedLegacyDrink = drinkStore.drinks.first { $0.id == record.id }
                            }
                        } label: {
                            JournalEntryRow(entry: displayEntry(for: record))
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
            if librarySnapshot.tasteRecords.isEmpty {
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

    /// Journal rows use the richer star scale. Legacy thumbs map to the locked
    /// 1/3/5 migration so old history is visible and editable without lying
    /// about precision the old schema never stored.
    private func displayEntry(for record: BeerTasteRecord) -> JournalEntry {
        JournalEntry(
            id: record.id,
            beerName: record.name,
            brand: record.brewery,
            style: record.style,
            abv: record.abv,
            rating: record.stars ?? stars(for: record.rating),
            notes: record.notes,
            photoFileName: record.photoFileName,
            dateLogged: record.date,
            dateTried: record.date
        )
    }

    private func stars(for rating: Rating) -> Int {
        switch rating {
        case .like: return 5
        case .neutral: return 3
        case .dislike: return 1
        }
    }

    /// First edit of a Drink-only legacy row writes a separate Journal record
    /// at the original encounter time. The projection then pairs them one-to-
    /// one, with Journal as authority, while CloudKit record IDs stay distinct.
    private func migrateLegacyDrink(_ drink: Drink, rating: Int, notes: String?) {
        let entry = JournalEntry(
            beerName: drink.name,
            brand: drink.brand,
            style: drink.style,
            abv: drink.abv,
            rating: rating,
            notes: notes,
            photoFileName: drink.photoFileName,
            dateLogged: drink.dateAdded,
            dateTried: drink.dateAdded
        )
        journalStore.addEntry(entry)
        scanStore.markTried(
            beerName: drink.name,
            brewery: drink.brand,
            linkedJournalId: entry.id
        )
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

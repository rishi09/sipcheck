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
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

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
                .padding(.bottom, 20)
            }
        }
        .accessibilityIdentifier("journalTab")
        .sheet(isPresented: $showingAddBeer) {
            if let scan = selectedWantToTryScan {
                AddBeerView(prefill: AddBeerPrefill(
                    name: scan.beerName,
                    style: scan.style ?? BeerStyle.other.rawValue,
                    abv: scan.abv
                ))
                .environmentObject(drinkStore)
                .environmentObject(journalStore)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(SipColors.textSecondary)

            TextField("Search your beers...", text: $searchText)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityIdentifier("journalSearch")
        }
        .padding(12)
        .background(SipColors.surface)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(JournalFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(_ filter: JournalFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button(action: {
            selectedFilter = filter
        }) {
            Text(filter.rawValue)
                .font(SipTypography.subhead)
                .foregroundColor(isSelected ? Color.black : SipColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? SipColors.primary : SipColors.surface)
                .cornerRadius(20)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Want to Try")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.primary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(scanStore.wantToTryScans) { scan in
                        WantToTryCard(scan: scan) {
                            selectedWantToTryScan = scan
                            showingAddBeer = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Tried Section

    private var triedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tried \u{00B7} \(filteredEntries.count) beers")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .padding(.horizontal, 16)

            if filteredEntries.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        JournalEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mug")
                .font(.system(size: 36))
                .foregroundColor(SipColors.textSecondary)

            Text("No beers found")
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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

import SwiftUI

enum SortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case name = "Name"
    case rating = "Rating"
    case style = "Style"

    var systemImage: String {
        switch self {
        case .dateAdded: return "calendar"
        case .name: return "textformat.abc"
        case .rating: return "star"
        case .style: return "tag"
        }
    }
}

struct BeerListView: View {
    @EnvironmentObject private var drinkStore: DrinkStore

    @State private var searchText = ""
    @State private var selectedRatingFilter: Rating?
    @State private var selectedStyleFilter: BeerStyle?
    @State private var selectedTypeFilter: DrinkType?
    @State private var sortOption: SortOption = .dateAdded

    private var filteredDrinks: [Drink] {
        let filtered = drinkStore.drinks.filter { drink in
            // Search filter (includes notes)
            let matchesSearch = searchText.isEmpty ||
                drink.name.localizedCaseInsensitiveContains(searchText) ||
                drink.brand.localizedCaseInsensitiveContains(searchText) ||
                (drink.notes ?? "").localizedCaseInsensitiveContains(searchText)

            // Rating filter
            let matchesRating = selectedRatingFilter == nil || drink.rating == selectedRatingFilter

            // Style filter
            let matchesStyle = selectedStyleFilter == nil || drink.style == selectedStyleFilter?.rawValue

            // Type filter
            let matchesType = selectedTypeFilter == nil || drink.drinkType == selectedTypeFilter

            return matchesSearch && matchesRating && matchesStyle && matchesType
        }

        // Apply sort after filtering
        switch sortOption {
        case .dateAdded:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .rating:
            return filtered.sorted { $0.ratingValue > $1.ratingValue }
        case .style:
            return filtered.sorted { $0.style.localizedCaseInsensitiveCompare($1.style) == .orderedAscending }
        }
    }

    private var hasActiveFilters: Bool {
        selectedRatingFilter != nil || selectedStyleFilter != nil || selectedTypeFilter != nil
    }

    var body: some View {
        List {
            if filteredDrinks.isEmpty {
                ContentUnavailableView {
                    Label("No Beers", systemImage: "mug")
                } description: {
                    if drinkStore.drinks.isEmpty {
                        Text("Add your first beer to get started!")
                    } else {
                        Text("No beers match your filters")
                    }
                }
            } else {
                ForEach(filteredDrinks) { drink in
                    NavigationLink {
                        BeerDetailView(drink: drink)
                    } label: {
                        BeerRowView(drink: drink)
                    }
                    .accessibilityIdentifier("beer_\(drink.id.uuidString)")
                }
                .onDelete { offsets in
                    drinkStore.deleteDrinks(at: offsets, from: filteredDrinks)
                }
            }
        }
        .navigationTitle("All Beers")
        .searchable(text: $searchText, prompt: "Search beers...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort options")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Rating filter
                    Menu("Rating") {
                        Button("All Ratings") {
                            selectedRatingFilter = nil
                        }
                        ForEach(Rating.allCases, id: \.self) { rating in
                            Button("\(rating.emoji) \(rating.displayName)") {
                                selectedRatingFilter = rating
                            }
                        }
                    }

                    // Style filter
                    Menu("Style") {
                        Button("All Styles") {
                            selectedStyleFilter = nil
                        }
                        ForEach(BeerStyle.allCases, id: \.self) { style in
                            Button(style.displayName) {
                                selectedStyleFilter = style
                            }
                        }
                    }

                    // Type filter
                    Menu("Type") {
                        Button("All Types") {
                            selectedTypeFilter = nil
                        }
                        ForEach(DrinkType.allCases, id: \.self) { type in
                            Button(type.displayName) {
                                selectedTypeFilter = type
                            }
                        }
                    }

                    if hasActiveFilters {
                        Divider()
                        Button("Clear Filters", role: .destructive) {
                            selectedRatingFilter = nil
                            selectedStyleFilter = nil
                            selectedTypeFilter = nil
                        }
                    }
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

struct BeerRowView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    let drink: Drink

    var body: some View {
        HStack {
            // Photo thumbnail or placeholder
            Group {
                if let fileName = drink.photoFileName,
                   let image = drinkStore.loadPhoto(named: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "mug")
                                .foregroundColor(.gray)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(drink.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    if !drink.brand.isEmpty {
                        Text(drink.brand)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text("• \(drink.style)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let abv = drink.abv {
                        Text("• \(String(format: "%.1f", abv))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            Text(drink.rating.emoji)
                .font(.title2)
        }
        .padding(.vertical, 4)
    }
}

struct BeerListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BeerListView()
                .environmentObject(DrinkStore())
        }
    }
}

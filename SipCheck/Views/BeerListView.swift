import SwiftUI

struct BeerListView: View {
    @EnvironmentObject private var drinkStore: DrinkStore

    @State private var searchText = ""
    @State private var selectedRatingFilter: Rating?
    @State private var selectedStyleFilter: BeerStyle?

    private var filteredDrinks: [Drink] {
        drinkStore.drinks.filter { drink in
            // Search filter
            let matchesSearch = searchText.isEmpty ||
                drink.name.localizedCaseInsensitiveContains(searchText) ||
                drink.brand.localizedCaseInsensitiveContains(searchText)

            // Rating filter
            let matchesRating = selectedRatingFilter == nil || drink.rating == selectedRatingFilter

            // Style filter
            let matchesStyle = selectedStyleFilter == nil || drink.style == selectedStyleFilter?.rawValue

            return matchesSearch && matchesRating && matchesStyle
        }
    }

    private var hasActiveFilters: Bool {
        selectedRatingFilter != nil || selectedStyleFilter != nil
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

                    if hasActiveFilters {
                        Divider()
                        Button("Clear Filters", role: .destructive) {
                            selectedRatingFilter = nil
                            selectedStyleFilter = nil
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
    let drink: Drink

    var body: some View {
        HStack {
            // Placeholder thumbnail
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "mug")
                        .foregroundColor(.gray)
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

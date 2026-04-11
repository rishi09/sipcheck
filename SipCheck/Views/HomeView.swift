import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var journalStore: JournalStore

    @State private var showingAddBeer = false
    @State private var showingCheckBeer = false
    @State private var showingBeerList = false
    @State private var showingStats = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App title
                Text("SipCheck")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                // Main action buttons
                VStack(spacing: 16) {
                    // Add Beer button
                    Button {
                        showingAddBeer = true
                    } label: {
                        Label("Add Beer", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .accessibilityIdentifier("addBeer")

                    // Check Beer button
                    Button {
                        showingCheckBeer = true
                    } label: {
                        Label("Check Beer", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(12)
                    }
                    .accessibilityIdentifier("checkBeer")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Empty state for fresh install
                if drinkStore.drinks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mug")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No beers yet!")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap Add Beer to get started.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                // Recent beers section
                if !drinkStore.drinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        // Taste profile summary
                        if drinkStore.drinks.count >= 3 {
                            let profile = drinkStore.tasteProfile
                            HStack(spacing: 16) {
                                VStack {
                                    Text("\(profile.totalDrinks)")
                                        .font(.title2).fontWeight(.bold)
                                    Text("Tried")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                VStack {
                                    Text("\(profile.likedCount)")
                                        .font(.title2).fontWeight(.bold).foregroundColor(.green)
                                    Text("Liked")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                if let topStyle = profile.favoriteStyles.first {
                                    VStack {
                                        Text(topStyle.style)
                                            .font(.title3).fontWeight(.semibold)
                                        Text("Top Style")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(12)
                        }

                        Text("Recent:")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ForEach(drinkStore.recentDrinks) { drink in
                            HStack {
                                Text("• \(drink.name)")
                                Spacer()
                                Text(drink.rating.emoji)
                            }
                            .font(.subheadline)
                        }

                        Button {
                            showingBeerList = true
                        } label: {
                            Text("See All Beers")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.top, 4)

                        Button {
                            showingStats = true
                        } label: {
                            Text("View Stats")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .sheet(isPresented: $showingAddBeer) {
                AddBeerView()
                    .environmentObject(drinkStore)
                    .environmentObject(journalStore)
            }
            .sheet(isPresented: $showingCheckBeer) {
                CheckBeerView()
            }
            .navigationDestination(isPresented: $showingBeerList) {
                BeerListView()
            }
            .navigationDestination(isPresented: $showingStats) {
                StatsView()
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(DrinkStore())
    }
}

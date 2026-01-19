import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var drinkStore: DrinkStore

    @State private var showingAddBeer = false
    @State private var showingCheckBeer = false
    @State private var showingBeerList = false

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
                }
                .padding(.horizontal, 32)

                Spacer()

                // Recent beers section
                if !drinkStore.drinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .sheet(isPresented: $showingAddBeer) {
                AddBeerView()
            }
            .sheet(isPresented: $showingCheckBeer) {
                CheckBeerView()
            }
            .navigationDestination(isPresented: $showingBeerList) {
                BeerListView()
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

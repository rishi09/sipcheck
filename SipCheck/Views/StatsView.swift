import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @State private var showingExportSheet = false
    @State private var exportURL: URL?

    // NOTE: profile, ratingBreakdown, styleBreakdown, and timelineSection are computed
    // properties that do full array passes. In a future refactor, these should be cached
    // in a @StateObject StatsViewModel that only recomputes when drinks actually changes.

    private var profile: TasteProfile {
        drinkStore.tasteProfile
    }

    var body: some View {
        // Cache snapshot of drinks so each section reads from the same array reference
        let drinks = drinkStore.drinks

        ScrollView {
            VStack(spacing: 20) {
                if drinks.isEmpty {
                    ContentUnavailableView {
                        Label("No Stats Yet", systemImage: "chart.bar")
                    } description: {
                        Text("Add some beers to see your stats!")
                    }
                } else {
                    overviewCards
                    ratingBreakdown
                    styleBreakdown
                    timelineSection
                    exportSection
                }
            }
            .padding()
        }
        .navigationTitle("Stats")
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        HStack(spacing: 12) {
            StatCard(title: "Total", value: "\(profile.totalDrinks)", color: .accentColor)
            StatCard(title: "Liked", value: "\(profile.likedCount)", color: .green)
            StatCard(title: "Disliked", value: "\(profile.dislikedCount)", color: .red)
            if let avgABV = profile.averageABV {
                StatCard(title: "Avg ABV", value: String(format: "%.1f%%", avgABV), color: .orange)
            }
        }
    }

    // MARK: - Rating Breakdown

    private var ratingBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating Distribution")
                .font(.headline)

            let total = max(drinkStore.drinks.count, 1)
            let liked = drinkStore.drinks.filter { $0.rating == .like }.count
            let neutral = drinkStore.drinks.filter { $0.rating == .neutral }.count
            let disliked = drinkStore.drinks.filter { $0.rating == .dislike }.count

            RatingBar(label: "Liked", emoji: Rating.like.emoji, count: liked, total: total, color: .green)
            RatingBar(label: "Neutral", emoji: Rating.neutral.emoji, count: neutral, total: total, color: .yellow)
            RatingBar(label: "Disliked", emoji: Rating.dislike.emoji, count: disliked, total: total, color: .red)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Style Breakdown

    private var styleBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Styles Tried")
                .font(.headline)

            let styleCounts = Dictionary(grouping: drinkStore.drinks, by: { $0.style })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }

            ForEach(styleCounts.prefix(8), id: \.key) { style, count in
                HStack {
                    Text(style)
                        .font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(count) / CGFloat(max(styleCounts.first?.value ?? 1, 1)))
                    }
                    .frame(width: 80, height: 12)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            let calendar = Calendar.current
            let grouped = Dictionary(grouping: drinkStore.drinks) { drink in
                calendar.dateComponents([.year, .month], from: drink.dateAdded)
            }
            .sorted { a, b in
                let aDate = calendar.date(from: a.key) ?? .distantPast
                let bDate = calendar.date(from: b.key) ?? .distantPast
                return aDate > bDate
            }

            ForEach(grouped.prefix(6), id: \.key) { components, drinks in
                let date = calendar.date(from: components) ?? Date()
                HStack {
                    Text(date.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text("\(drinks.count) beers")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(spacing: 12) {
            Button {
                exportAsJSON()
            } label: {
                Label("Export as JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(12)
            }

            Button {
                exportAsCSV()
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(12)
            }
        }
    }

    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(drinkStore.drinks) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.json")
        try? data.write(to: tempURL)
        exportURL = tempURL
        showingExportSheet = true
    }

    private func exportAsCSV() {
        var csv = "Name,Brand,Style,Rating,ABV,Type,Notes,Date\n"
        for drink in drinkStore.drinks {
            let name = drink.name.replacingOccurrences(of: ",", with: ";")
            let brand = drink.brand.replacingOccurrences(of: ",", with: ";")
            let notes = (drink.notes ?? "").replacingOccurrences(of: ",", with: ";")
            let abv = drink.abv.map { String(format: "%.1f", $0) } ?? ""
            let date = drink.dateAdded.formatted(.iso8601)
            csv += "\(name),\(brand),\(drink.style),\(drink.rating.displayName),\(abv),\(drink.drinkType.displayName),\(notes),\(date)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = tempURL
        showingExportSheet = true
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct RatingBar: View {
    let label: String
    let emoji: String
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack {
            Text("\(emoji) \(label)")
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(total))
                }
            }
            .frame(height: 16)
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 30)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StatsView()
                .environmentObject(DrinkStore())
        }
    }
}

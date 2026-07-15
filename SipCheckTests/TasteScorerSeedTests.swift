import XCTest
@testable import SipCheck

/// Invariants for the onboarding avoid-seed ("stay away") and go-to style
/// channels in TasteScorer + TastePreferences.
final class TasteScorerSeedTests: XCTestCase {

    // MARK: - Fixtures

    /// Preferences with everything defaulted except the fields under test.
    private func prefs(
        vibe: String = "",
        adventure: String = "",
        dislikes: [String] = [],
        seedStyles: [String] = [],
        goToStyles: [String] = [],
        avoidStyles: [String] = []
    ) -> TastePreferences {
        TastePreferences(
            vibe: vibe,
            adventure: adventure,
            dislikes: dislikes,
            seedStyles: seedStyles,
            goToStyles: goToStyles,
            avoidStyles: avoidStyles
        )
    }

    private var emptyProfile: TasteProfile { TasteProfile() }

    // MARK: - 1. Avoid seed alone vetoes the style

    func testAvoidSeededStyleIsSkipItWithSteerClearReason() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertLessThanOrEqual(assessment.score, -5.5)
        XCTAssertTrue(
            assessment.shortReason.contains("you steer clear of stout"),
            "Got reason: \(assessment.shortReason)"
        )
    }

    // MARK: - 2. Vibe cannot cancel an explicit avoid pick

    func testVibeDoesNotCancelAvoidSeed() {
        let preferences = prefs(vibe: "Dark & Roasty", avoidStyles: ["Stout"])

        let stout = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: preferences
        )
        XCTAssertEqual(stout.verdict, .skipIt, "Explicit stay-away must beat a vibe match")

        // A sibling dark style stays boosted by the vibe (+2.0 -> tryIt).
        let porter = TasteScorer.assess(
            name: "Dock Porter",
            style: .porter,
            abv: nil,
            profile: emptyProfile,
            preferences: preferences
        )
        XCTAssertEqual(porter.verdict, .tryIt)
        XCTAssertEqual(porter.score, 2.0, accuracy: 0.0001)
    }

    // MARK: - 3. Rated LIKE history nets the avoid seed to mixed evidence

    func testRatedLikeHistoryNetsAvoidSeedToMixed() {
        var profile = TasteProfile()
        profile.favoriteStyles = [(style: "Stout", count: 5)]

        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: profile,
            preferences: prefs(avoidStyles: ["Stout"])
        )
        // Liked weight caps at 3.0; netted against the shared 3.0 offset -> 0.0.
        XCTAssertEqual(assessment.score, 0.0, accuracy: 0.0001)
        XCTAssertEqual(assessment.verdict, .yourCall)
        XCTAssertTrue(
            assessment.shortReason.contains("mixed history with stout"),
            "Got reason: \(assessment.shortReason)"
        )
    }

    // MARK: - 4. Avoid wins style-key conflicts against seed and go-to

    func testAvoidWinsWhenStyleIsAlsoSeeded() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(seedStyles: ["Stout"], avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        // The +1.5 seed weight must never be applied on top of the avoid penalty.
        XCTAssertEqual(assessment.score, -5.5, accuracy: 0.0001)
    }

    func testAvoidWinsWhenStyleIsAlsoGoTo() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(goToStyles: ["Stout"], avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        // The +2.0 go-to weight must never be applied on top of the avoid penalty.
        XCTAssertEqual(assessment.score, -5.5, accuracy: 0.0001)
    }

    // MARK: - 5. Menu ranking: quiz dislike (-5.0) ranks ahead of avoid seed (-5.5)

    func testQuizDislikeRanksAheadOfAvoidSeed() {
        let preferences = prefs(dislikes: ["Really Sour"], avoidStyles: ["Stout"])
        let profile = emptyProfile

        let sour = TasteScorer.AssessedCandidate(
            name: "Puckerfest",
            style: .sour,
            abv: nil,
            assessment: TasteScorer.assess(
                name: "Puckerfest", style: .sour, abv: nil,
                profile: profile, preferences: preferences
            )
        )
        let stout = TasteScorer.AssessedCandidate(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            assessment: TasteScorer.assess(
                name: "Midnight Roast", style: .stout, abv: nil,
                profile: profile, preferences: preferences
            )
        )

        XCTAssertEqual(sour.assessment.score, -5.0, accuracy: 0.0001)
        XCTAssertEqual(stout.assessment.score, -5.5, accuracy: 0.0001)
        XCTAssertTrue(TasteScorer.ranksAhead(sour, stout, profile: profile, preferences: preferences))
        XCTAssertFalse(TasteScorer.ranksAhead(stout, sour, profile: profile, preferences: preferences))
    }

    // MARK: - 6. Regression pin: empty avoid/go-to leaves scores unchanged

    func testEmptyAvoidAndGoToLeaveScoresUnchanged() {
        // Pre-change fixture: vibe + adventure + quiz dislike + beer-derived seed,
        // with the NEW fields empty. Scores must match the pre-change formula.
        let preferences = prefs(
            vibe: "Hoppy & Bitter",
            adventure: "Mix It Up",
            dislikes: ["Really Sour"],
            seedStyles: ["Wheat"]
        )
        let profile = emptyProfile

        let ipa = TasteScorer.assess(
            name: "Hop Cannon", style: .ipa, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(ipa.score, 2.0, accuracy: 0.0001)   // vibe weight
        XCTAssertEqual(ipa.verdict, .tryIt)

        let wheat = TasteScorer.assess(
            name: "Cloud Cover", style: .wheat, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(wheat.score, 1.5, accuracy: 0.0001) // seed weight
        XCTAssertEqual(wheat.verdict, .yourCall)

        let sour = TasteScorer.assess(
            name: "Puckerfest", style: .sour, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(sour.score, -5.0, accuracy: 0.0001) // quiz dislike
        XCTAssertEqual(sour.verdict, .skipIt)

        let lager = TasteScorer.assess(
            name: "Crisp One", style: .lager, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(lager.score, 0.2, accuracy: 0.0001) // neutral, "Mix It Up"
        XCTAssertEqual(lager.verdict, .yourCall)
    }

    // MARK: - 7. saveAvoidBeers pushes empties (seed-save semantics)

    func testSaveAvoidBeersPushesEmpties() {
        let defaults = UserDefaults.standard
        let cloud = NSUbiquitousKeyValueStore.default
        let keys = ["avoidBeers", "tasteAvoidStyles"]
        let originals = keys.map { ($0, defaults.string(forKey: $0)) }
        // saveAvoidBeers write-throughs the iCloud KVS too (the unit-test host
        // launches WITHOUT the hermetic args, so cloudDisabled is false), and
        // seedValue treats a PRESENT-but-empty cloud value as authoritative —
        // restoring only UserDefaults would leave this test's final empty
        // save shadowing (and sync-erasing) real stay-away picks on any
        // iCloud-signed-in device.
        let cloudOriginals = keys.map { ($0, cloud.string(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            for (key, value) in cloudOriginals {
                if let value {
                    cloud.set(value, forKey: key)
                } else {
                    cloud.removeObject(forKey: key)
                }
            }
            cloud.synchronize()
        }

        TastePreferences.saveAvoidBeers(["Guinness", "Sour"], avoidStyles: ["Stout", "Sour"])
        XCTAssertEqual(defaults.string(forKey: "avoidBeers"), "Guinness,Sour")
        XCTAssertEqual(defaults.string(forKey: "tasteAvoidStyles"), "Sour,Stout")

        // Clearing the picker must write PRESENT-but-empty values (never nil):
        // an empty seed value is authoritative and must propagate.
        TastePreferences.saveAvoidBeers([], avoidStyles: [])
        XCTAssertEqual(defaults.string(forKey: "avoidBeers"), "")
        XCTAssertEqual(defaults.string(forKey: "tasteAvoidStyles"), "")
        XCTAssertEqual(TastePreferences.savedAvoidBeers, [])
    }

    // MARK: - 8. Go-to style chip scores at the vibe weight

    func testGoToStyleScoresTryIt() {
        let assessment = TasteScorer.assess(
            name: "Hop Cannon",
            style: .ipa,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(goToStyles: ["IPA"])
        )
        XCTAssertEqual(assessment.score, 2.0, accuracy: 0.0001)
        XCTAssertEqual(assessment.verdict, .tryIt)
    }

    func testEveryOnboardingBeerMapsToAColdStartStyle() {
        for beer in onboardingBeerOptions {
            XCTAssertNotNil(
                TastePreferences.styleForOnboardingBeer(beer),
                "Missing cold-start style for \(beer)"
            )
        }
        XCTAssertEqual(TastePreferences.styleForOnboardingBeer("Lagunitas"), .ipa)
        XCTAssertEqual(TastePreferences.styleForOnboardingBeer("Guinness"), .stout)
    }

    func testNamedGoToBeerGetsExplicitGoToWeight() {
        let defaults = UserDefaults.standard
        let keys = ["knownBeers", "tasteSeedStyles", "tasteGoToStyles"]
        let originals = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        TastePreferences.saveGoTo(beers: ["Lagunitas"], styleChips: [], seedStyles: ["IPA"])

        XCTAssertEqual(defaults.string(forKey: "tasteSeedStyles"), "IPA")
        XCTAssertEqual(defaults.string(forKey: "tasteGoToStyles"), "IPA")
        let assessment = TasteScorer.assess(
            name: "Two Hearted",
            style: .ipa,
            abv: 7.0,
            profile: emptyProfile,
            preferences: TastePreferences.current
        )
        XCTAssertEqual(assessment.verdict, .tryIt)
    }

    func testManyLikesOutweighOneHistoricalDislike() {
        let drinks = (0..<10).map { _ in
            Drink(name: UUID().uuidString, style: "IPA", rating: .like)
        } + [Drink(name: "One miss", style: "IPA", rating: .dislike)]
        let assessment = TasteScorer.assess(
            name: "Two Hearted",
            style: .ipa,
            abv: nil,
            profile: TasteProfile.build(from: drinks),
            preferences: prefs()
        )

        XCTAssertEqual(assessment.verdict, .tryIt)
        XCTAssertEqual(assessment.score, 3.0, accuracy: 0.0001)
        XCTAssertTrue(assessment.shortReason.contains("matches your history"))
    }

    func testHistoricalDislikesStillWinWhenTheyOutnumberLikes() {
        let drinks = [
            Drink(name: "Liked once", style: "Stout", rating: .like),
            Drink(name: "Miss 1", style: "Stout", rating: .dislike),
            Drink(name: "Miss 2", style: "Stout", rating: .dislike),
            Drink(name: "Miss 3", style: "Stout", rating: .dislike)
        ]
        let assessment = TasteScorer.assess(
            name: "Dark Beer",
            style: .stout,
            abv: nil,
            profile: TasteProfile.build(from: drinks),
            preferences: prefs()
        )

        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertEqual(assessment.score, -1.5, accuracy: 0.0001)
    }

    func testExactPriorRatingOverridesAggregateStyleVerdict() {
        let base = TasteScorer.assess(
            name: "Known Beer",
            style: .paleAle,
            abv: nil,
            profile: TasteProfile(),
            preferences: prefs()
        )

        XCTAssertEqual(TasteScorer.applyingExactRating(.like, to: base).verdict, .tryIt)
        XCTAssertEqual(TasteScorer.applyingExactRating(.dislike, to: base).verdict, .skipIt)
        XCTAssertEqual(TasteScorer.applyingExactRating(.neutral, to: base).verdict, .yourCall)
        XCTAssertEqual(TasteScorer.applyingExactRating(nil, to: base).verdict, base.verdict)
    }
}

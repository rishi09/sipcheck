import XCTest
@testable import SipCheck

/// Executable recommendation oracles for the evidence-backed behavioral modes
/// in plans/reports/BEER_DRINKER_ARCHETYPES.md.
final class RecommendationArchetypeEvalTests: XCTestCase {

    private struct CandidateOracle {
        let fixtureName: String
        let beerName: String
        let style: BeerStyle
        let abv: Double?
        let expectedVerdict: Verdict
        let expectedReasonFragment: String
    }

    private struct ArchetypeOracle {
        let name: String
        let history: [Drink]
        let preferences: TastePreferences
        let candidates: [CandidateOracle]
    }

    func testTasteScorerMatchesNamedArchetypeOracles() {
        for archetype in archetypeOracles {
            let profile = TasteProfile.build(from: archetype.history)

            for candidate in archetype.candidates {
                let assessment = TasteScorer.assess(
                    name: candidate.beerName,
                    style: candidate.style,
                    abv: candidate.abv,
                    profile: profile,
                    preferences: archetype.preferences
                )
                let context = failureContext(
                    archetype: archetype,
                    candidate: candidate,
                    assessment: assessment
                )

                XCTAssertEqual(
                    assessment.verdict,
                    candidate.expectedVerdict,
                    context
                )
                XCTAssertTrue(
                    assessment.shortReason.contains(candidate.expectedReasonFragment),
                    "\(context); expected reason containing \"\(candidate.expectedReasonFragment)\""
                )
            }
        }
    }

    func testExplicitStayAwayBeatsExactPositiveHistory() {
        let previouslyLikedBeer = liked(
            "Boundary Stout",
            style: .stout,
            abv: 7.5
        )
        let history = [previouslyLikedBeer]
        let assessment = TasteScorer.assessWithExactHistory(
            name: previouslyLikedBeer.name,
            style: .stout,
            abv: previouslyLikedBeer.abv,
            drinks: history,
            profile: TasteProfile.build(from: history),
            preferences: preferences(
                adventure: "Give Me the Weird Stuff",
                avoidStyles: [.stout]
            )
        )

        XCTAssertEqual(
            assessment.verdict,
            .skipIt,
            "An explicit current stay-away choice must beat an exact historical like; "
                + assessmentDescription(assessment)
        )
        XCTAssertLessThan(
            assessment.score,
            0,
            "A hard avoid must remain below the SKIP threshold; "
                + assessmentDescription(assessment)
        )
        XCTAssertTrue(
            assessment.shortReason.contains("you steer clear of stout"),
            "A hard avoid must explain the explicit preference; "
                + assessmentDescription(assessment)
        )
    }

    private var archetypeOracles: [ArchetypeOracle] {
        [
            ArchetypeOracle(
                name: "Familiarity-first lager loyalist",
                history: [
                    liked("Weeknight Lager 1", style: .lager, abv: 4.2),
                    liked("Weeknight Lager 2", style: .lager, abv: 4.3),
                    liked("Weeknight Lager 3", style: .lager, abv: 4.4),
                    liked("Weeknight Lager 4", style: .lager, abv: 4.5)
                ],
                preferences: preferences(
                    adventure: "Stick to Favorites",
                    goToStyles: [.lager]
                ),
                candidates: [
                    CandidateOracle(
                        fixtureName: "positive - adjacent craft pilsner",
                        beerName: "Aisle Seven Pilsner",
                        style: .pilsner,
                        abv: 4.8,
                        expectedVerdict: .tryIt,
                        expectedReasonFragment: "close to the styles"
                    ),
                    CandidateOracle(
                        fixtureName: "negative - distant fruit sour",
                        beerName: "Raspberry Current",
                        style: .sour,
                        abv: 5.0,
                        expectedVerdict: .skipIt,
                        expectedReasonFragment: "outside the styles"
                    ),
                    CandidateOracle(
                        fixtureName: "negative - heavy roasted stout",
                        beerName: "Imperial Night Stout",
                        style: .stout,
                        abv: 9.5,
                        expectedVerdict: .skipIt,
                        expectedReasonFragment: "outside the styles"
                    ),
                    CandidateOracle(
                        fixtureName: "negative - hop-heavy hazy IPA",
                        beerName: "Hazy Hop Charge",
                        style: .ipa,
                        abv: 7.0,
                        expectedVerdict: .skipIt,
                        expectedReasonFragment: "outside the styles"
                    )
                ]
            ),
            ArchetypeOracle(
                name: "Cautious dark-malt adjacent explorer",
                history: [
                    liked("Roast House 1", style: .stout, abv: 6.5),
                    liked("Roast House 2", style: .stout, abv: 6.8),
                    liked("Roast House 3", style: .stout, abv: 7.0)
                ],
                preferences: preferences(
                    adventure: "Stick to Favorites",
                    goToStyles: [.stout]
                ),
                candidates: [
                    CandidateOracle(
                        fixtureName: "positive - one-step porter",
                        beerName: "Dockside Porter",
                        style: .porter,
                        abv: 6.2,
                        expectedVerdict: .tryIt,
                        expectedReasonFragment: "close to the styles"
                    ),
                    CandidateOracle(
                        fixtureName: "negative - distant West Coast IPA",
                        beerName: "Breakwater West Coast IPA",
                        style: .ipa,
                        abv: 6.8,
                        expectedVerdict: .skipIt,
                        expectedReasonFragment: "outside the styles"
                    )
                ]
            ),
            ArchetypeOracle(
                name: "Hop specialist without sour evidence",
                history: [
                    liked("House IPA 1", style: .ipa, abv: 6.2),
                    liked("House IPA 2", style: .ipa, abv: 6.5),
                    liked("House IPA 3", style: .ipa, abv: 6.8)
                ],
                preferences: preferences(
                    vibe: "Hoppy & Bitter",
                    adventure: "Mix It Up",
                    goToStyles: [.ipa]
                ),
                candidates: [
                    CandidateOracle(
                        fixtureName: "positive - pale ale in the hop family",
                        beerName: "Trailhead Pale Ale",
                        style: .paleAle,
                        abv: 5.5,
                        expectedVerdict: .tryIt,
                        expectedReasonFragment: "matches your love of pale ale"
                    ),
                    CandidateOracle(
                        fixtureName: "honest call - sour needs independent evidence",
                        beerName: "Orchard Gose",
                        style: .sour,
                        abv: 5.0,
                        expectedVerdict: .yourCall,
                        expectedReasonFragment: "no strong signal"
                    )
                ]
            ),
            ArchetypeOracle(
                name: "Sour specialist without dark-malt evidence",
                history: [
                    liked("Cellar Sour 1", style: .sour, abv: 5.0),
                    liked("Cellar Sour 2", style: .sour, abv: 5.4)
                ],
                preferences: preferences(
                    vibe: "Sour & Weird",
                    adventure: "Mix It Up",
                    goToStyles: [.sour]
                ),
                candidates: [
                    CandidateOracle(
                        fixtureName: "positive - gose in the sour family",
                        beerName: "Salt Air Gose",
                        style: .sour,
                        abv: 4.8,
                        expectedVerdict: .tryIt,
                        expectedReasonFragment: "matches your history with sour"
                    ),
                    CandidateOracle(
                        fixtureName: "honest call - stout needs dark evidence",
                        beerName: "Midnight Stout",
                        style: .stout,
                        abv: 7.0,
                        expectedVerdict: .yourCall,
                        expectedReasonFragment: "no strong signal"
                    )
                ]
            ),
            ArchetypeOracle(
                name: "Broad explorer with an explicit boundary",
                history: [
                    liked("Abbey Dubbel", style: .belgian, abv: 7.0),
                    liked("Farmhouse Ale", style: .belgian, abv: 6.5),
                    liked("Citrus IPA", style: .ipa, abv: 6.5),
                    liked("Brown Porter", style: .porter, abv: 5.8),
                    liked("Cloud Wheat", style: .wheat, abv: 5.1),
                    liked("Crisp Lager", style: .lager, abv: 4.6),
                    liked("Boundary Stout", style: .stout, abv: 7.5)
                ],
                preferences: preferences(
                    adventure: "Give Me the Weird Stuff",
                    avoidStyles: [.stout]
                ),
                candidates: [
                    CandidateOracle(
                        fixtureName: "positive - unfamiliar saison with known family fit",
                        beerName: "Meadow Saison",
                        style: .belgian,
                        abv: 6.2,
                        expectedVerdict: .tryIt,
                        expectedReasonFragment: "matches your history with belgian"
                    ),
                    CandidateOracle(
                        fixtureName: "negative - explicit boundary beats broad history",
                        beerName: "Boundary Stout",
                        style: .stout,
                        abv: 7.5,
                        expectedVerdict: .skipIt,
                        expectedReasonFragment: "you steer clear of stout"
                    )
                ]
            ),
            ArchetypeOracle(
                name: "Sparse-history drinker",
                history: [
                    liked("One Wheat", style: .wheat, abv: 5.2)
                ],
                preferences: preferences(adventure: "Stick to Favorites"),
                candidates: [
                    CandidateOracle(
                        fixtureName: "honest call - one related rating is not confidence",
                        beerName: "Another Hefeweizen",
                        style: .wheat,
                        abv: 5.0,
                        expectedVerdict: .yourCall,
                        expectedReasonFragment: "matches your history with wheat"
                    ),
                    CandidateOracle(
                        fixtureName: "honest call - distant extreme lacks evidence",
                        beerName: "House Sour",
                        style: .sour,
                        abv: 5.0,
                        expectedVerdict: .yourCall,
                        expectedReasonFragment: "no strong signal"
                    )
                ]
            )
        ]
    }

    private func preferences(
        vibe: String = "",
        adventure: String = "",
        dislikes: [String] = [],
        seedStyles: [BeerStyle] = [],
        goToStyles: [BeerStyle] = [],
        avoidStyles: [BeerStyle] = []
    ) -> TastePreferences {
        TastePreferences(
            vibe: vibe,
            adventure: adventure,
            dislikes: dislikes,
            seedStyles: seedStyles.map(\.rawValue),
            goToStyles: goToStyles.map(\.rawValue),
            avoidStyles: avoidStyles.map(\.rawValue)
        )
    }

    private func liked(_ name: String, style: BeerStyle, abv: Double) -> Drink {
        Drink(name: name, style: style.rawValue, rating: .like, abv: abv)
    }

    private func failureContext(
        archetype: ArchetypeOracle,
        candidate: CandidateOracle,
        assessment: TasteScorer.Assessment
    ) -> String {
        "\(archetype.name) / \(candidate.fixtureName) / \(candidate.beerName) "
            + "expected \(candidate.expectedVerdict.rawValue); "
            + assessmentDescription(assessment)
    }

    private func assessmentDescription(_ assessment: TasteScorer.Assessment) -> String {
        "got \(assessment.verdict.rawValue), score \(assessment.score), "
            + "reason \"\(assessment.shortReason)\""
    }
}

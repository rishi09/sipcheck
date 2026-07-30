# Long-Tail Beer Search Provider Evaluation

**Status:** Decision record, July 30, 2026

**Decision:** Use Advanced Tavily search as asynchronous evidence retrieval and Gemini as a bounded fact extractor. Keep SipCheck's local resolver and `TasteScorer` on the immediate path and as the recommendation authority.

## Stable Product Context

SipCheck is for beer enthusiasts, so the beer someone wants is often a local microbrew, a seasonal release, or otherwise absent from a bundled catalog. Pliny and Smog City are examples of the class of problem, not records to hardcode.

Use these principles when revisiting the tradeoff:

1. Do not assume that a wanted beer is already in SipCheck's catalog.
2. Limited connectivity is a constraint, but not a reason for connected search to return no result for the long tail.
3. A local miss is a trigger for remote discovery, not the final search result.
4. Preserve the fast offline path: resolve and score immediately with whatever local facts are available, then refine from remote evidence asynchronously.
5. Apply one generic discovery pipeline to mainstream and obscure beers. Do not add per-beer exceptions.
6. Remote models retrieve and normalize facts. They do not decide whether the user should drink the beer; the local scorer applies the same preference and history rules.
7. Prefer a sourced abstention over invented identity or style when evidence conflicts. ABV is optional enrichment and must never gate a result.
8. Send the minimum required search context. Taste profile, ratings, history, notes, photos, and location are not search inputs.

## Evaluation Design

The cold test corpus contained ten long-tail beers. Each Tavily mode ran three independent trials per beer, for 30 trials per mode. The primary product bar is strict identity plus a supported coarse scorer category when the source establishes one; an unknown category must remain unknown and produce a cautious local verdict. ABV is a secondary diagnostic only. "Official" includes a first-party source or a source wired to the producer. Latency is end-to-end Tavily retrieval plus Gemini extraction.

These results characterize this corpus and test environment; they are not a guarantee for all beers or future provider behavior.

An implementation audit corrected the original category count. The first scorer treated any Czech `pivo` (which only means "beer") as lager, making Snímek's generic `Silné Pivo (Strong Beer)` look category-ready without supporting evidence. The strict identity, source, latency, token, and credit counts below are unchanged. Advanced's defensible category-ready count is 27/30, while the historical Basic category count cannot be reconstructed from the retained aggregate data. Snímek now remains category-unknown unless a selected source explicitly supplies a style such as lager.

## Measured Results

| Metric | Basic Tavily + Gemini | Advanced Tavily + bounded raw evidence + Gemini |
|---|---:|---:|
| Strict identity | 24/30 | 30/30 |
| **Identity + supported coarse category** | Not reconstructible | **27/30** |
| Identity + category + exact ABV (secondary) | 21/30 | 27/30 |
| First-party/official-wired source | 18/30 | 24/30 |
| Median latency | 2,174 ms | 5,344 ms |
| p95 latency | 3,047 ms | 7,513 ms |
| Maximum latency | 3,323 ms | 7,673 ms |
| Tavily credits | 30 | 60 |
| Average Gemini tokens | 1,388 | 11,187 |

### Per-Beer Outcomes

Each cell is successful trials out of three. "Exact facts" includes ABV and is retained only as a secondary diagnostic; it is not the search success criterion.

| Beer | Advanced recommendation-ready | Basic exact facts | Advanced exact facts | Advanced official source | Observation |
|---|---:|---:|---:|---:|---|
| Drink Beer Slay Dragon | **3/3** | 3/3 | 3/3 | 3/3 | Basic and Advanced were complete. |
| Redwood | **3/3** | 0/3 | 0/3 | 3/3 | The correct identity and category were found; only the stale official ABV missed the secondary check. |
| Snímek | **0/3 category; 3/3 identity** | 1/3 | 3/3 | 3/3 | The source supports `Strong Beer`, not a coarse lager category. The result must remain searchable but category-unknown. |
| Jantar | **3/3** | 2/3 | 3/3 | 3/3 | Advanced was complete. |
| Whipple Street | **3/3** | 3/3 | 3/3 | 0/3 | Facts were usable, but the evidence source was Untappd rather than official. |
| Stratasphere | **3/3** | 2/3 | 3/3 | 0/3 | Advanced fixed the fact miss; the evidence source remained Untappd. |
| Scout | **3/3** | 3/3 | 3/3 | 3/3 | Basic and Advanced were complete. |
| SKYLAB | **3/3** | 2/3 | 3/3 | 3/3 | One Basic trial returned `Sky Lab`; facts and category were otherwise correct. |
| SENATE BEER | **3/3** | 3/3 | 3/3 | 3/3 | Advanced improved source quality. |
| BIG TOMORROW | **3/3** | 2/3 | 3/3 | 3/3 | Advanced was complete. |

### Google Comparator

Google-grounded Gemini 3.5 reached 30/30 strict identity and 24/30 identity/category/ABV trials, covering 8/10 beers exactly, at a median around 2.2 seconds. A multi-search variant fixed Snímek but not Drink Beer Slay Dragon's stale ABV and reached a best of 9/10 exact beers. The retained aggregate does not separate Google category misses from ABV-only misses. Plain Gemini without search evidence was not viable for this long-tail task.

Despite the strong retrieval result, Google Search Grounding was not selected for this architecture. Our reading of the current published terms requires display of grounded results and search suggestions and restricts extracting, analyzing, caching, or storing grounded output in the way SipCheck's local scoring and persistence flow requires. This is an engineering constraint assessment, not legal advice.

## Provider Screening

| Candidate | Product and cost fit | Persistence/terms posture | Outcome |
|---|---|---|---|
| Tavily | Search is designed for AI retrieval. Free plan provides 1,000 monthly credits; Basic costs one credit and Advanced costs two. | The standard terms do not present the same explicit caching ban found in Brave's standard terms, but they also do not grant an express ownership or persistence license for returned content. Query data may be used to improve responses and may be shared with search-index providers. | Selected technically, with raw evidence transient and written confirmation still appropriate before external distribution. |
| Google Search Grounding | Best measured latency/quality combination on much of this corpus. | Current Grounding requirements do not fit hidden extraction into a locally scored, persistable result. | Rejected for the current architecture. |
| Brave Search API | Automatic monthly credit can cover about 1,000 Search requests, but payment details are required. | Standard terms expressly restrict storing, caching, building a database from, making derivative works from, or redistributing Search Results except for transient use. | Rejected absent a custom agreement. |
| Exa | Monthly free credit and inexpensive search make it operationally plausible. | Documentation supports factual lookup and structured extraction, while the public terms contain broader restrictions on copying or downloading information. Long-lived derived-fact persistence remains unclear without written permission. | Not selected; contractual ambiguity remains. |

## Decision and Runtime Boundary

Advanced Tavily was selected because it produced strict identity in 30/30 trials and a supported coarse category in 27/30, while Basic missed six identities. Unknown category evidence now stays unknown rather than being forced into a recommendation bucket. The roughly 5.3-second median is acceptable only because it is not the verdict's critical path:

1. SipCheck checks typed text and local catalog data immediately.
2. The local scorer produces the best available verdict from current facts, preferences, and history.
3. For an unresolved or incomplete long-tail query, the backend sends only the typed search text to Tavily.
4. Gemini converts bounded returned evidence into typed beer identity, style, source, and optional ABV fields.
5. SipCheck validates and merges those fields, then reruns the same local scorer. The remote model never receives the taste profile and never returns the recommendation.
6. Normalized facts and a source URL may be persisted when the user acts on the result. Raw snippets and page content remain transient.

This can visibly refine a verdict after remote facts arrive. That is expected when the original local facts were incomplete; the UI should preserve provenance so the change is understandable rather than appearing arbitrary.

## Reproducible Regression Set

The non-secret golden cases are committed at `backend/eval/golden-set.json`. They record accepted beer and brewery aliases, the supported coarse category (or explicit unknown), and allowed source hosts for the same ten long-tail beers. `backend/eval/run-live-eval.ts` runs one live request per case and fails unless it gets:

- identity on 10/10 cases;
- the correct category on all nine category-adjudicable cases;
- an allowed public HTTPS source on 10/10 cases.

It also records first-party rate and median/p95 latency. ABV is not scored. A full run costs 20 Tavily credits, so it is manual rather than attached to every code push:

```bash
cd backend
npm run eval:live -- --output ../plans/reports/LONG_TAIL_LIVE_EVAL.json
```

Unit tests exercise the evaluator without provider calls. The latest generated result is retained at `plans/reports/LONG_TAIL_LIVE_EVAL.json`. The historical comparison predates this harness and did not retain raw per-trial responses; future provider or prompt changes must preserve the generated live result artifact so their evidence is independently inspectable.

## Credit Economics and Guardrail

- Tavily's free plan resets to 1,000 credits on the first day of each month.
- Basic search costs one credit, allowing at most 1,000 Basic searches per free-plan month.
- Advanced search costs two credits, allowing at most 500 Advanced searches per free-plan month.
- The 30-trial evaluation used 30 Basic credits and 60 Advanced credits.
- The daily/manual GitHub usage guard fails at 80% account-plan usage. On a 1,000-credit plan that is 800 credits, or 400 Advanced searches, leaving 200 credits (100 Advanced searches) for intervention time.
- Gemini token charges or quota are separate and are not included in the Tavily credit counts. Advanced's measured 11,187-token average is an additional cost and latency consideration.
- Pay-as-you-go should remain disabled until traffic, abuse controls, per-user throttling, and a firm spend cap are established.

The usage guard calls Tavily's stateless `/usage` endpoint. It reports plan usage and remaining credits in the GitHub job summary without logging the API key or response body.

## Limitations and Review Triggers

- Ten beers and 60 historical Tavily trials are useful directional evidence, not broad catalog coverage.
- The corpus intentionally stresses the long tail; it does not measure common-beer performance.
- First-party does not always mean current. Redwood's stale official ABV caused every Advanced secondary exact-fact miss, while all three trials still met the identity/category product bar.
- The historical evaluation retained aggregates but not raw per-trial responses. The committed golden set and runner make subsequent decisions reproducible; they cannot reconstruct missing historical detail.
- Source classification measures provenance, not factual correctness. Untappd supplied usable facts for two beers but was not counted as official.
- Network latency and provider ranking can change by geography, time, index state, and model version.
- Provider terms and privacy policies can change. Review them before a public launch, and obtain written permission or counsel where normalized-fact persistence is material.
- The production endpoint is intentionally anonymous so the app can use it without shipping provider keys. Tavily's hard plan quota and the daily 80% guard prevent a surprise bill and provide warning, but they do not stop a third party from exhausting the free allowance. Add App Attest-backed abuse controls before broad public distribution if real traffic or abuse appears.
- Typed discovery waits for at least three normalized characters and a 650 ms pause before starting connected search, which avoids spending provider quota on ordinary in-progress keystrokes without changing the local instant path.
- Re-evaluate the provider or mode if identity/category accuracy drops below the local product bar, median/p95 latency harms the interaction, average token volume grows materially, or monthly usage approaches the guardrail.

## Primary Sources

- [Tavily API credits](https://docs.tavily.com/documentation/api-credits)
- [Tavily usage endpoint](https://docs.tavily.com/documentation/api-reference/endpoint/usage)
- [Tavily rate limits](https://docs.tavily.com/documentation/rate-limits)
- [Tavily terms](https://www.tavily.com/terms)
- [Tavily privacy policy](https://www.tavily.com/privacy)
- [Gemini API additional terms](https://ai.google.dev/gemini-api/terms)
- [Brave Search API pricing](https://brave.com/search/api/)
- [Brave Search API terms](https://api-dashboard.search.brave.com/terms-of-service)
- [Exa pricing](https://exa.ai/docs/reference/pricing)
- [Exa terms](https://exa.ai/assets/Exa_Labs_Terms_of_Service.pdf)

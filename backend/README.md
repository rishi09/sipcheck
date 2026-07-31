# SipCheck beer-search proxy

Vercel function for long-tail beer discovery. It searches Tavily, then uses
Gemini only to extract facts from the returned evidence. Gemini does not use a
search tool.

Beer identity, brewery, style, and a source URL are the useful discovery facts.
ABV is nullable enrichment and never gates whether a result is returned. Tavily
also returns image candidates. Whether an image came from the verified source
page or the top-level image pool, its own description or URL path must ground
the exact beer and brewery. Every accepted candidate must include a packaging
cue such as a can, bottle, label, or product shot; posters, menus, event art,
and merchandise are rejected. Gemini never receives or generates image URLs.

Configure the Vercel project's root directory as `backend` and set these server
environment variables:

- `TAVILY_API_KEY`
- `GEMINI_API_KEY`

The `sipcheck-beer-search` Vercel project is connected to this GitHub repository
with `backend/` as its project root. Branch commits receive preview deployments;
`main` is the production branch. The TestFlight workflow resolves and tests the
Vercel deployment attached to its exact Git commit before building the app.

The endpoint is `POST /api/beer-search`:

```json
{"query":"Falling Knife Catch","limit":6}
```

Successful responses use the iOS client's public `name` field:

```json
{
  "results": [
    {
      "name": "Falling Knife Catch",
      "brewery": "ISM Brewing",
      "style": "West Coast IPA",
      "abv": 6.6,
      "source_url": "https://ism.beer/drink-menu",
      "image_url": "https://images.ism.beer/falling-knife-catch-can.webp"
    }
  ]
}
```

`image_url` is omitted when no candidate meets the exact identity, product, and
public-HTTPS URL-shape checks. These checks are intentionally described as URL
validation, not as DNS or private-network classification. The URL is reference
artwork for a searched beer, not a claim that the user photographed it.

`GET /api/health` performs no provider calls and reports the public contract
version plus whether each required provider secret is configured.

Neither upstream evidence nor extracted results are cached or logged by this
service. Run `npm test` and `npm run typecheck` before deployment.

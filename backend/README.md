# SipCheck beer-search proxy

Vercel function for long-tail beer discovery. It searches Tavily, then uses
Gemini only to extract facts from the returned evidence. Gemini does not use a
search tool.

Configure the Vercel project's root directory as `backend` and set these server
environment variables:

- `TAVILY_API_KEY`
- `GEMINI_API_KEY`

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
      "source_url": "https://ism.beer/drink-menu"
    }
  ]
}
```

`GET /api/health` performs no provider calls and reports only whether each
required provider secret is configured.

Neither upstream evidence nor extracted results are cached or logged by this
service. Run the dependency-free unit suite with `npm test`.

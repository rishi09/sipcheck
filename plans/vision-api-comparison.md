# Beer Label Scanning Speed Research
**Date: March 10, 2026 | Target: Under 2 seconds end-to-end**

> Status note: this is time-sensitive vendor research, not a record of the current implementation. Model pricing, latency, and deprecation details may have changed since this was written. Use it for direction, not as canonical project state.

## Executive Summary

For a grocery-store beer label scan with a sub-2-second target, **Gemini 2.0 Flash** is the recommended cloud API (0.34s TTFB, 257 tok/s, $0.10/MTok input). The **optimal architecture** is a **hybrid approach**: Apple Vision OCR on-device (~100-200ms) to extract label text, then send extracted text to a fast text-only LLM (Gemini 2.0 Flash or GPT-4.1 mini). This eliminates image upload latency entirely and can reliably hit sub-1-second total time.

---

## Decision Matrix

| Option | TTFB | Output Speed | Est. Total Latency* | Cost/Request** | Quality | Offline? | iOS SDK |
|---|---|---|---|---|---|---|---|
| **GPT-4o Vision** | 0.51s | 143 tok/s | 2.5-6s | ~$0.003-0.005 | Excellent | No | REST API |
| **GPT-4o-mini Vision** | 0.35s | 65 tok/s | 2-4s | ~$0.0005 | Good | No | REST API |
| **GPT-4.1 mini Vision** | ~0.3s (est.) | ~100+ tok/s (est.) | 1.5-3s | ~$0.0005 | Good+ | No | REST API |
| **Gemini 2.0 Flash** | **0.34s** | **257 tok/s** | **0.8-1.5s** | **~$0.0002** | Good+ | No | REST API / Google AI SDK |
| **Claude Haiku 4.5** | 0.88s*** | 51 tok/s | 2-4s | ~$0.002 | Good+ | No | REST API |
| **Apple Vision OCR** | **0ms (on-device)** | N/A | **100-300ms** | **$0 (free)** | Text only (no beer ID) | **Yes** | Native (Vision framework) |
| **Hybrid: OCR + text LLM** | 100ms + 0.34s | 257 tok/s | **0.5-1.2s** | ~$0.0001 | Good+ | Partial | Native + REST |
| **Apple FastVLM (on-device)** | **<120ms** | ~10-30 tok/s (est.) | **0.5-2s** | **$0 (free)** | Moderate | **Yes** | CoreML (experimental) |

\* End-to-end: image capture + network round-trip + model processing + response parsing. Assumes good cellular/WiFi.
\** Based on a single beer label photo (~765 tokens for GPT, ~258-1000 tokens for Gemini, ~1300 tokens for Claude) + ~50-100 output tokens.
\*** Claude Haiku 4.5 TTFB appears anomalously high on some benchmarks (39.9s on one source, 0.88s on another). The 0.88s figure is from Claude 3.5 Haiku which is the more realistic comparable.

---

## Detailed Analysis

### 1. GPT-4o Vision (Current Implementation)

**Latency:** TTFB 0.51s, 143 tokens/sec output. Real-world vision requests show 2.7-5.8 seconds total (community reports). Highly variable.

**Pricing:**
- Input: $2.50/MTok
- Output: $10.00/MTok
- Typical beer label scan: ~765 input tokens (image) + 100 system prompt + ~75 output tokens = ~$0.003

**Verdict:** Too slow for grocery store use case. 3-6 seconds is frustrating when standing in an aisle comparing beers.

Sources: [OpenAI Community Forum](https://community.openai.com/t/openai-api-vision-model-response-time-unstable-and-sometimes-slow/1146824), [Vellum Leaderboard](https://www.vellum.ai/llm-leaderboard)

---

### 2. GPT-4o-mini Vision

**Latency:** TTFB 0.35s, but only 65 tokens/sec output (slower output than GPT-4o). Total ~2-4 seconds for vision tasks.

**Pricing:**
- Input: $0.15/MTok
- Output: $0.60/MTok
- Typical scan: ~$0.0005

**Verdict:** Cheaper but not faster. Community reports indicate vision quality is also worse than GPT-4o, with more refusals to analyze images.

Sources: [Artificial Analysis - GPT-4o mini](https://artificialanalysis.ai/models/gpt-4o-mini), [OpenAI Community](https://community.openai.com/t/4o-vs-4o-mini-vision-api-speed-testing/876228)

---

### 3. GPT-4.1 mini (newer alternative)

**Latency:** Claims "nearly half the latency of GPT-4o." Likely TTFB around 0.25-0.35s.

**Pricing:**
- Input: $0.40/MTok
- Output: $1.60/MTok
- Typical scan: ~$0.0005

**Verdict:** Promising middle ground. Newer model, reportedly faster, but limited real-world vision benchmarks available. Worth testing.

Sources: [DocsBot - GPT-4.1 Mini](https://docsbot.ai/models/gpt-4-1-mini), [LiveChatAI Pricing](https://livechatai.com/gpt-4-1-mini-pricing-calculator)

---

### 4. Gemini 2.0 Flash

**Latency:** TTFB 0.34s via Google AI Studio. 257 tokens/sec output (fastest of all tested models). TTFB 0.46s via Vertex AI.

**Pricing:**
- Input: $0.10/MTok
- Output: $0.40/MTok
- Image: ~258-1000 tokens depending on resolution
- Typical scan: ~$0.0001-0.0002

**Verdict: BEST cloud-only option.** Fastest TTFB, fastest output, and cheapest. For a short response (beer name + style + brand = ~50 tokens), total API time could be under 1 second. Network round-trip adds ~100-300ms. Total: ~0.7-1.5s.

Note: Gemini 2.0 Flash is deprecated June 1, 2026. Successor is **Gemini 2.5 Flash** (TTFB 0.35s, 200 tok/s, $0.15/MTok input) which is nearly as fast.

Sources: [Artificial Analysis - Gemini 2.0 Flash](https://artificialanalysis.ai/models/gemini-2-0-flash/providers), [Google Pricing](https://ai.google.dev/gemini-api/docs/pricing), [Vellum Leaderboard](https://www.vellum.ai/llm-leaderboard)

---

### 5. Claude Haiku 4.5

**Latency:** Anthropic calls it their "fastest model" (4-5x faster than Sonnet). But benchmarks show TTFB 0.88s and only 51 tokens/sec output. Image token overhead is high (~1,333 tokens for a 1000x1000 image using formula: width*height/750).

**Pricing:**
- Input: $1.00/MTok
- Output: $5.00/MTok
- Typical scan: ~$0.002

**Verdict:** Too slow and too expensive for this use case. The high image token count and slower output speed make it a poor fit for sub-2-second scanning.

Sources: [Anthropic Haiku](https://www.anthropic.com/claude/haiku), [Anthropic Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [Vellum Leaderboard](https://www.vellum.ai/llm-leaderboard)

---

### 6. Apple Vision Framework (On-Device OCR)

**Latency:** On-device, no network required. Two modes:
- `.fast` mode: Estimated 50-150ms for text extraction
- `.accurate` mode: Estimated 200-500ms

**Pricing:** Free (built into iOS)

**Quality:** Extracts text only. Very good at reading printed labels. Will get "Blue Moon Belgian White Wheat Ale" but cannot infer beer style from visual cues alone. Cannot identify a brand from a logo without readable text.

**Verdict:** Excellent first stage in a hybrid pipeline. Extracts text in ~100ms, works offline, zero cost. But needs an LLM to interpret the text into structured beer data.

Sources: [Create with Swift](https://www.createwithswift.com/recognizing-text-with-the-vision-framework/), [Hacking with Swift](https://www.hackingwithswift.com/example-code/vision/how-to-use-vnrecognizetextrequests-optical-character-recognition-to-detect-text-in-an-image)

---

### 7. Hybrid: Apple OCR On-Device + Text-Only LLM

**Architecture:**
1. Capture image (instant)
2. Run VNRecognizeTextRequest on-device (~100-150ms)
3. Send extracted text to text-only Gemini 2.0 Flash (~300-500ms total)
4. Parse response (~10ms)

**Total estimated latency: 0.5-1.0 seconds**

**Why this is faster:**
- No image upload over cellular (a 500KB JPEG over LTE takes 200-500ms just to upload)
- Text-only API calls are faster than vision calls (no image processing on server)
- Text payload is ~200 bytes vs ~200-500KB for an image
- Lower token count = faster processing

**Pricing:** ~$0.00005-0.0001 per request (text only, minimal tokens)

**Quality:** Depends on OCR accuracy. Beer labels with clear text work great. Heavily stylized/artistic labels may lose some text. Could fall back to full vision API for low-confidence OCR results.

**Verdict: RECOMMENDED APPROACH.** Sub-second total latency, cheapest option, partially works offline (OCR step), and degrades gracefully.

---

### 8. Apple FastVLM (On-Device Vision-Language Model)

**Latency:** Under 120ms time-to-first-token on iPhone 16 Pro for the 0.5B model. 85x faster than LLaVA-OneVision.

**Quality:** Moderate. The 0.5B model has lower accuracy than cloud APIs on visual QA benchmarks (ChartQA 76.0, TextVQA 64.5). The 7B model is much better but would be slower on-device.

**Pricing:** Free (on-device)

**Status:** Open-source from Apple (CVPR 2025). Requires CoreML conversion. No official Apple framework integration yet. Experimental.

**Verdict:** Most promising future option. If SipCheck could ship a fine-tuned 0.5B model trained on beer labels, this could be instant and fully offline. However, it requires significant engineering effort and the model quality may not be sufficient without fine-tuning.

Sources: [FastVLM](https://fastvlm.net/), [BrightCoding Analysis](https://www.blog.brightcoding.dev/2025/09/17/fastvlm-the-breakthrough-in-on-device-vision-language-ai/), [Ultralytics Blog](https://www.ultralytics.com/blog/fastvlm-apple-introduces-its-new-fast-vision-language-model)

---

## How Vivino and Similar Apps Do It

**Vivino** uses Vuforia cloud-based image recognition (not an LLM). They match wine label images against a pre-built database of millions of labels. This is fundamentally different from LLM-based recognition - it is a visual fingerprinting/matching approach, not generative AI. Results are fast (~1-2s) because it is a lookup, not generation.

**Untappd** uses barcode scanning for known beers in their database. Not image recognition of labels.

**Cal AI** (food calorie scanner) uses a vision LLM (likely GPT-4o or similar) and typically takes 2-4 seconds.

Sources: [PTC Vivino Case Study](https://www.ptc.com/en/case-studies/vivino), [Uncheckd](https://uncheckd.com/)

---

## Recommendation for SipCheck

### Immediate (ship this week):
**Switch from GPT-4o to Gemini 2.0 Flash** for the vision API call. This alone should cut latency from 3-6s to ~1-1.5s with minimal code changes. Use `detail: low` on images to reduce token count. Compress/resize images to 512x512 before sending.

### Short-term (next sprint):
**Implement the hybrid approach:**
1. Add `VNRecognizeTextRequest` to extract text on-device (~100ms)
2. Send extracted text to Gemini 2.0 Flash (or 2.5 Flash) text-only endpoint
3. Keep the full vision API as a fallback for when OCR confidence is low
4. Target: sub-1-second for 80% of scans

### Medium-term (future):
- Evaluate **Apple FastVLM** as it matures for fully offline scanning
- Consider building a beer label database for instant fingerprint matching (Vivino-style) if the app reaches scale
- Move to **Gemini 2.5 Flash** before 2.0 Flash deprecation (June 2026)

### Prompt for text-only LLM (hybrid approach):
```
Given the following text extracted from a beer label, identify:
- Beer name
- Brewery/brand
- Style (IPA, Stout, Lager, etc.)
- ABV (if visible)

Respond in JSON format. If unsure about any field, use null.

Label text: {extracted_text}
```

---

## Cost Comparison at Scale (10,000 scans/month)

| Approach | Monthly Cost |
|---|---|
| GPT-4o Vision (current) | ~$30-50 |
| GPT-4o-mini Vision | ~$5 |
| Gemini 2.0 Flash Vision | ~$2 |
| Hybrid OCR + Gemini text | ~$0.50-1.00 |
| Apple FastVLM (on-device) | $0 |

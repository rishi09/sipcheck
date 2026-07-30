import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  evaluateGoldenCase,
  type GoldenBeerCase,
  type PublicBeerResult
} from "../src/eval.ts";

const DEFAULT_ENDPOINT = "https://sipcheck-beer-search.vercel.app/api/beer-search";
const EXPECTED_CONTRACT = "tavily-gemini-v1";
const REQUEST_TIMEOUT_MS = 30_000;

interface CaseReport {
  id: string;
  query: string;
  latency_ms: number;
  identity: boolean;
  category: boolean | null;
  expected_category: string | null;
  actual_category: string | null;
  source: boolean;
  official_source: boolean;
  result: PublicBeerResult | null;
  error?: string;
}

function outputArgument(): string | null {
  const index = process.argv.indexOf("--output");
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : null;
}

function percentile(values: number[], fraction: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.ceil(sorted.length * fraction) - 1];
}

async function fetchJSON(url: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    cache: "no-store"
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const contentType = response.headers.get("content-type") ?? "unknown content type";
  const body = await response.text();
  try {
    return JSON.parse(body) as unknown;
  } catch {
    throw new Error(`Expected JSON from ${new URL(url).host}, received ${contentType}`);
  }
}

function publicResults(payload: unknown): PublicBeerResult[] {
  if (typeof payload !== "object" || payload === null || !("results" in payload)) return [];
  const results = (payload as { results?: unknown }).results;
  return Array.isArray(results) ? results as PublicBeerResult[] : [];
}

async function main(): Promise<void> {
  const directory = dirname(fileURLToPath(import.meta.url));
  const golden = JSON.parse(
    await readFile(resolve(directory, "golden-set.json"), "utf8")
  ) as GoldenBeerCase[];
  const endpoint = process.env.BEER_SEARCH_URL?.trim() || DEFAULT_ENDPOINT;
  const healthURL = new URL("health", endpoint).toString();
  const health = await fetchJSON(healthURL) as { contract?: unknown };
  if (health.contract !== EXPECTED_CONTRACT) {
    throw new Error(`Expected ${EXPECTED_CONTRACT}, received ${String(health.contract)}`);
  }

  const cases: CaseReport[] = [];
  for (const expected of golden) {
    const started = performance.now();
    try {
      const payload = await fetchJSON(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ query: expected.query, limit: 4 })
      });
      const latency = Math.round(performance.now() - started);
      const evaluation = evaluateGoldenCase(expected, publicResults(payload));
      cases.push({
        id: expected.id,
        query: expected.query,
        latency_ms: latency,
        identity: evaluation.identity,
        category: evaluation.category,
        expected_category: expected.coarse_category,
        actual_category: evaluation.actualCategory,
        source: evaluation.source,
        official_source: evaluation.officialSource,
        result: evaluation.result
      });
    } catch (error) {
      cases.push({
        id: expected.id,
        query: expected.query,
        latency_ms: Math.round(performance.now() - started),
        identity: false,
        category: expected.coarse_category === null ? null : false,
        expected_category: expected.coarse_category,
        actual_category: null,
        source: false,
        official_source: false,
        result: null,
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    const current = cases[cases.length - 1];
    console.log([
      current.identity && current.category !== false && current.source ? "PASS" : "FAIL",
      current.id,
      `identity=${current.identity}`,
      `category=${String(current.category)}`,
      `source=${current.source}`,
      `${current.latency_ms}ms`
    ].join(" "));
  }

  const categoryCases = cases.filter((item) => item.category !== null);
  const latencies = cases.map((item) => item.latency_ms);
  const summary = {
    identity: `${cases.filter((item) => item.identity).length}/${cases.length}`,
    category: `${categoryCases.filter((item) => item.category).length}/${categoryCases.length}`,
    source: `${cases.filter((item) => item.source).length}/${cases.length}`,
    official_source: `${cases.filter((item) => item.official_source).length}/${cases.length}`,
    median_latency_ms: percentile(latencies, 0.5),
    p95_latency_ms: percentile(latencies, 0.95)
  };
  const report = {
    generated_at: new Date().toISOString(),
    endpoint,
    contract: EXPECTED_CONTRACT,
    credits: cases.length * 2,
    summary,
    cases
  };
  console.log(JSON.stringify(summary));

  const output = outputArgument();
  if (output) await writeFile(resolve(output), `${JSON.stringify(report, null, 2)}\n`, "utf8");

  const passed = summary.identity === `${cases.length}/${cases.length}`
    && summary.category === `${categoryCases.length}/${categoryCases.length}`
    && summary.source === `${cases.length}/${cases.length}`;
  if (!passed) process.exitCode = 1;
}

await main();

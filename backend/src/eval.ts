export interface GoldenBeerCase {
  id: string;
  query: string;
  beer_aliases: string[];
  brewery_aliases: string[];
  style_evidence: string;
  coarse_category: string | null;
  official_hosts: string[];
  credible_hosts: string[];
  source_urls: string[];
  notes?: string;
}

export interface PublicBeerResult {
  name: string;
  brewery: string;
  style: string | null;
  abv?: number | null;
  source_url: string;
}

export interface CaseEvaluation {
  identity: boolean;
  category: boolean | null;
  source: boolean;
  officialSource: boolean;
  actualCategory: string | null;
  result: PublicBeerResult | null;
}

export function normalizeEvalText(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("en-US")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function matchesAlias(value: string, aliases: string[]): boolean {
  const normalized = normalizeEvalText(value);
  return aliases.some((alias) => normalizeEvalText(alias) === normalized);
}

function sourceHost(raw: string): string | null {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    return url.hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return null;
  }
}

function hostMatches(host: string | null, allowed: string[]): boolean {
  return host !== null && allowed.some((candidate) =>
    host === candidate || host.endsWith(`.${candidate}`)
  );
}

export function inferEvalCategory(style: string | null): string | null {
  if (!style) return null;
  const value = ` ${normalizeEvalText(style)} `;
  if (/\bipa\b|\bindia pale ale\b/.test(value)) return "ipa";
  if (/\blager\b|\bhelles\b|\bcream ale\b|\bcerveza\b|\blezak\b/.test(value)) return "lager";
  if (/\bamber\b|\bred ale\b|\bmarzen\b|\boktoberfest\b/.test(value)) return "amber";
  if (/\bstout\b/.test(value)) return "stout";
  if (/\bporter\b/.test(value)) return "porter";
  if (/\bwheat\b|\bhefeweizen\b|\bwitbier\b/.test(value)) return "wheat";
  if (/\bsour\b|\bgose\b|\blambic\b/.test(value)) return "sour";
  if (/\bpilsner\b|\bpils\b/.test(value)) return "pilsner";
  if (/\bbelgian\b|\bsaison\b|\btripel\b|\bdubbel\b/.test(value)) return "belgian";
  if (/\bbrown ale\b/.test(value)) return "brownAle";
  if (/\bpale ale\b|\bgolden ale\b|\bblonde\b/.test(value)) return "paleAle";
  return null;
}

export function evaluateGoldenCase(
  expected: GoldenBeerCase,
  results: PublicBeerResult[]
): CaseEvaluation {
  const identityMatches = results.filter((result) =>
    matchesAlias(result.name, expected.beer_aliases)
      && matchesAlias(result.brewery, expected.brewery_aliases)
  );
  const allowedHosts = [...expected.official_hosts, ...expected.credible_hosts];
  const ranked = identityMatches.map((result) => {
    const actualCategory = inferEvalCategory(result.style);
    const host = sourceHost(result.source_url);
    return {
      result,
      actualCategory,
      source: hostMatches(host, allowedHosts),
      officialSource: hostMatches(host, expected.official_hosts),
      category: expected.coarse_category === null
        ? null
        : actualCategory === expected.coarse_category
    };
  }).sort((left, right) => {
    const score = (value: typeof left): number =>
      (value.category === true ? 4 : 0) + (value.source ? 2 : 0) + (value.officialSource ? 1 : 0);
    return score(right) - score(left);
  });
  const best = ranked[0];
  return {
    identity: identityMatches.length > 0,
    category: best?.category ?? (expected.coarse_category === null ? null : false),
    source: best?.source ?? false,
    officialSource: best?.officialSource ?? false,
    actualCategory: best?.actualCategory ?? null,
    result: best?.result ?? null
  };
}

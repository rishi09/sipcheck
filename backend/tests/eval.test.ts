import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluateGoldenCase,
  inferEvalCategory,
  normalizeEvalText,
  type GoldenBeerCase
} from "../src/eval.ts";

const expected: GoldenBeerCase = {
  id: "pliny",
  query: "Pliny IPA",
  beer_aliases: ["Pliny the Elder"],
  brewery_aliases: ["Russian River Brewing Company"],
  style_evidence: "Double IPA",
  coarse_category: "ipa",
  official_hosts: ["russianriverbrewing.com"],
  credible_hosts: ["untappd.com", "beeradvocate.com"],
  source_urls: []
};

test("eval normalization handles punctuation, spacing, and diacritics", () => {
  assert.equal(normalizeEvalText("  SNÍMEK—Silné  "), "snimek silne");
});

test("eval category inference does not treat generic pivo as lager", () => {
  assert.equal(inferEvalCategory("Silné Pivo (Strong Beer)"), null);
  assert.equal(inferEvalCategory("Světlý Ležák"), "lager");
  assert.equal(inferEvalCategory("West Coast IPA"), "ipa");
});

test("golden evaluation requires identity, category, and an allowed source", () => {
  const result = evaluateGoldenCase(expected, [{
    name: "Pliny the Elder",
    brewery: "Russian River Brewing Company",
    style: "Double IPA",
    source_url: "https://www.russianriverbrewing.com/pliny-the-elder"
  }]);
  assert.deepEqual(result, {
    identity: true,
    category: true,
    source: true,
    officialSource: true,
    actualCategory: "ipa",
    result: {
      name: "Pliny the Elder",
      brewery: "Russian River Brewing Company",
      style: "Double IPA",
      source_url: "https://www.russianriverbrewing.com/pliny-the-elder"
    }
  });
});

test("unknown expected category is excluded without weakening identity or source", () => {
  const result = evaluateGoldenCase({
    ...expected,
    coarse_category: null
  }, [{
    name: "Pliny the Elder",
    brewery: "Russian River Brewing Company",
    style: "Strong Beer",
    source_url: "https://untappd.com/b/example/1"
  }]);
  assert.equal(result.identity, true);
  assert.equal(result.category, null);
  assert.equal(result.source, true);
  assert.equal(result.officialSource, false);
});

test("BeerAdvocate is credible but not official, while arbitrary aggregators fail", () => {
  const beerAdvocate = evaluateGoldenCase(expected, [{
    name: "Pliny the Elder",
    brewery: "Russian River Brewing Company",
    style: "Double IPA",
    source_url: "https://www.beeradvocate.com/beer/profile/863/7971"
  }]);
  assert.equal(beerAdvocate.source, true);
  assert.equal(beerAdvocate.officialSource, false);

  const tapHunter = evaluateGoldenCase(expected, [{
    name: "Pliny the Elder",
    brewery: "Russian River Brewing Company",
    style: "Double IPA",
    source_url: "https://www.taphunter.com/beer/pliny/1"
  }]);
  assert.equal(tapHunter.source, false);
  assert.equal(tapHunter.officialSource, false);
});

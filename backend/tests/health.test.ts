import assert from "node:assert/strict";
import test from "node:test";

import { healthPayload } from "../src/health.ts";

test("health payload exposes configuration state without secret values", () => {
  const payload = healthPayload({
    TAVILY_API_KEY: "tavily-secret",
    GEMINI_API_KEY: "   "
  });

  assert.deepEqual(payload, {
    status: "ok",
    contract: "tavily-gemini-v1",
    providers: {
      tavily: true,
      gemini: false
    }
  });
  assert.equal(JSON.stringify(payload).includes("tavily-secret"), false);
});

test("health payload has the exact provider-free response shape", () => {
  assert.deepEqual(healthPayload({}), {
    status: "ok",
    contract: "tavily-gemini-v1",
    providers: {
      tavily: false,
      gemini: false
    }
  });
});

// src/app/api/health/route.test.ts
//
// This is a genuine (if minimal) test, not a placeholder to make CI green —
// it's here specifically because .github/workflows/ci.yml now runs
// `npm run test`, and a CI step that "passes" only because there's nothing
// to run is worse than no CI step at all (false confidence). More tests
// belong here as features accumulate — see backend/README.md and
// database/README.md for the fuller Phase 14 testing strategy this is a
// down payment on, not a substitute for.
import { describe, it, expect } from "vitest";
import { GET } from "./route";

describe("GET /api/health", () => {
  it("returns status ok with a timestamp", async () => {
    const response = await GET();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe("ok");
    expect(new Date(body.timestamp).toString()).not.toBe("Invalid Date");
  });
});

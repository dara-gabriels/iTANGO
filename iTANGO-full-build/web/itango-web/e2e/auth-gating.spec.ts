// e2e/auth-gating.spec.ts
//
// Covers what's testable WITHOUT live SMS delivery or a seeded Supabase
// test account — actually completing phone OTP login in an automated E2E
// run needs either a Supabase test-mode OTP bypass or a real SMS-reading
// step, neither of which exists in this build pass (flagged in e2e/README.md
// rather than faked with a hardcoded "always succeeds" mock that would
// test nothing real about the middleware/auth integration).

import { test, expect } from "@playwright/test";

test.describe("Unauthenticated access control", () => {
  test("visiting /organizer/events redirects to /login", async ({ page }) => {
    await page.goto("/organizer/events");
    await expect(page).toHaveURL(/\/login/);
  });

  test("visiting /admin/reports redirects to /login", async ({ page }) => {
    await page.goto("/admin/reports");
    await expect(page).toHaveURL(/\/login/);
  });

  test("visiting /home without a session redirects to /login", async ({ page }) => {
    await page.goto("/home");
    await expect(page).toHaveURL(/\/login/);
  });

  test("the health check endpoint is reachable without authentication", async ({ page }) => {
    // Regression test for the exact bug caught during Phase 15: this
    // endpoint was originally redirected to /login by the auth middleware
    // before the matcher exclusion was added. This test exists specifically
    // so that mistake can't silently come back.
    const response = await page.request.get("/api/health");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe("ok");
  });
});

test.describe("Login page", () => {
  test("rejects an invalid phone number before ever calling Supabase", async ({ page }) => {
    await page.goto("/login");
    await page.getByPlaceholder("+234 801 234 5678").fill("not-a-phone-number");
    await page.getByRole("button", { name: "Continue" }).click();

    await expect(page.getByText("Enter a valid phone number")).toBeVisible();
  });

  test("shows the OTP entry step after a valid-format phone number is submitted", async ({ page }) => {
    await page.goto("/login");
    await page.getByPlaceholder("+234 801 234 5678").fill("+2348012345678");
    await page.getByRole("button", { name: "Continue" }).click();

    // This only asserts the UI transitions to the OTP step — it does NOT
    // assert an SMS was actually sent (that requires a live Supabase
    // project + real phone number + SMS provider integration, none of
    // which belong in an automated CI run). A failed Supabase call here
    // would surface as an error toast instead of this step appearing,
    // which is still a meaningful assertion.
    await expect(page.getByText(/Enter the code sent to/)).toBeVisible({ timeout: 10_000 });
  });
});

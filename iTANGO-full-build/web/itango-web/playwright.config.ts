// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry",
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    // Mobile Safari included deliberately, not just Chrome — a meaningful
    // share of iTANGO's actual users will hit the public event pages from
    // an iPhone Safari share-link tap (WhatsApp/Instagram), and Safari has
    // historically diverged from Chromium on exactly the things this app
    // relies on (CSS gradients, PostHog cookie behavior).
    { name: "mobile-safari", use: { ...devices["iPhone 13"] } },
  ],
  // Only spin up a local server for local development. When E2E_BASE_URL
  // is set (staging/production runs — see deploy-staging.yml's e2e-tests
  // job), tests hit a real deployed environment and starting a redundant
  // local server would be pure wasted CI time at best.
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "npm run build && npm run start",
        url: "http://localhost:3000/api/health",
        reuseExistingServer: true,
        timeout: 120_000,
      },
});

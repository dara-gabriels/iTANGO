// sentry.client.config.ts
// Loaded automatically by @sentry/nextjs on the browser. Run:
//   npm install @sentry/nextjs
// then wrap next.config.js with withSentryConfig (see sentry-web-setup.md).

import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_ENVIRONMENT ?? "development",

  // 100% in staging (low volume, want full visibility while testing),
  // 10% in production (real user traffic — full tracing on every request
  // would be expensive and unnecessary for catching real issues).
  tracesSampleRate: process.env.NEXT_PUBLIC_ENVIRONMENT === "production" ? 0.1 : 1.0,

  // Never send Session Replay by default — it can capture screenshots of
  // the DOM, which for a nightlife/social app could include other users'
  // photos or messages rendered on screen. Only enable per-session with
  // explicit consent if this becomes a debugging priority later.
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 0,

  beforeSend(event) {
    // Strip anything that looks like a Supabase JWT from error messages/
    // extra data before it ever leaves the browser — belt-and-suspenders
    // beyond just "don't log tokens" in application code.
    if (event.request?.headers?.["Authorization"]) {
      delete event.request.headers["Authorization"];
    }
    return event;
  },
});

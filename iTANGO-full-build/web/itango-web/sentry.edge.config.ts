// sentry.edge.config.ts
// Separate from sentry.server.config.ts because Next.js Middleware
// (src/middleware.ts) runs in the Edge runtime, which has a different,
// more restricted API surface than the Node server runtime — @sentry/nextjs
// requires this split file rather than one shared config.
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_ENVIRONMENT ?? "development",
  tracesSampleRate: process.env.NEXT_PUBLIC_ENVIRONMENT === "production" ? 0.1 : 1.0,
});

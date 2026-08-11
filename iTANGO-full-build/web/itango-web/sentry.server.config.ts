// sentry.server.config.ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_ENVIRONMENT ?? "development",
  tracesSampleRate: process.env.NEXT_PUBLIC_ENVIRONMENT === "production" ? 0.1 : 1.0,

  beforeSend(event) {
    // Server-side errors are more likely to carry service-role-adjacent
    // context (query params, request bodies) than client errors — strip
    // anything under a `service_role` or `secret` key defensively.
    if (event.extra) {
      for (const key of Object.keys(event.extra)) {
        if (/secret|service_role|password/i.test(key)) {
          delete event.extra[key];
        }
      }
    }
    return event;
  },
});

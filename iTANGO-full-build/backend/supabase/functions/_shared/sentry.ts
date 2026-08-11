// supabase/functions/_shared/sentry.ts
//
// A minimal, direct-to-Sentry-API error reporter — NOT the official
// @sentry/node or @sentry/deno SDK. Rationale: Supabase Edge Functions run
// on a bespoke Deno-based Edge Runtime, not standard Deno or Deno Deploy,
// and there's no officially verified-compatible Sentry SDK for it at time
// of writing. Rather than import an SDK that might silently fail in this
// runtime (which would be worse than no monitoring — false confidence),
// this posts directly to Sentry's documented envelope ingestion API. This
// gets real error capture (message, stack trace, tags, environment) but
// deliberately doesn't attempt breadcrumbs, session tracking, or
// performance tracing — those need a real SDK, which is a legitimate
// follow-up once a Deno-Edge-Runtime-compatible one is verified to work here.
//
// Usage in any function's catch block:
//   import { reportError } from "../_shared/sentry.ts";
//   catch (err) {
//     await reportError(err, { function: "checkins", user_id: user?.id });
//     return handleKnownErrors(err);
//   }

interface SentryContext {
  function: string;
  [key: string]: unknown;
}

export async function reportError(error: unknown, context: SentryContext): Promise<void> {
  const dsn = Deno.env.get("SENTRY_DSN");
  if (!dsn) return; // Monitoring is additive — never throw because Sentry isn't configured.

  try {
    const { host, pathname, username } = new URL(dsn);
    const projectId = pathname.replace("/", "");
    const ingestUrl = `https://${host}/api/${projectId}/envelope/`;

    const eventId = crypto.randomUUID().replace(/-/g, "");
    const timestamp = new Date().toISOString();

    const errorMessage = error instanceof Error ? error.message : String(error);
    const stackTrace = error instanceof Error ? error.stack : undefined;

    const envelopeHeader = JSON.stringify({
      event_id: eventId,
      sent_at: timestamp,
      dsn,
    });

    const eventPayload = JSON.stringify({
      event_id: eventId,
      timestamp,
      platform: "other",
      environment: Deno.env.get("ENVIRONMENT") ?? "production",
      tags: { function: context.function },
      extra: context,
      exception: {
        values: [
          {
            type: error instanceof Error ? error.name : "Error",
            value: errorMessage,
            stacktrace: stackTrace ? { frames: parseStackTrace(stackTrace) } : undefined,
          },
        ],
      },
    });

    const itemHeader = JSON.stringify({ type: "event" });
    const envelope = `${envelopeHeader}\n${itemHeader}\n${eventPayload}`;

    await fetch(ingestUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-sentry-envelope",
        "X-Sentry-Auth": `Sentry sentry_version=7, sentry_client=itango-edge-reporter/1.0, sentry_key=${username}`,
      },
      body: envelope,
    });
  } catch (reportingError) {
    // Never let monitoring itself crash the function it's monitoring —
    // log locally and move on.
    console.error("Sentry reporting failed:", reportingError);
  }
}

/** Best-effort stack frame parsing — Sentry accepts a simplified frame list; exact V8 format isn't required for a readable stack trace in the dashboard. */
function parseStackTrace(stack: string): Array<{ function: string; filename: string }> {
  return stack
    .split("\n")
    .slice(1, 15) // cap frame count — this is a lightweight reporter, not a full SDK
    .map((line) => ({ function: line.trim(), filename: "edge-function" }));
}

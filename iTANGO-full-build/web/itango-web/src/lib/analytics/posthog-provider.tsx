// src/lib/analytics/posthog-provider.tsx
"use client";

import { useEffect } from "react";
import posthog from "posthog-js";
import { PostHogProvider as PHProvider } from "posthog-js/react";

export function PostHogProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    if (!process.env.NEXT_PUBLIC_POSTHOG_KEY) return; // no-op in local dev without a key configured

    posthog.init(process.env.NEXT_PUBLIC_POSTHOG_KEY, {
      api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com",
      // Capture pageviews manually on route change rather than PostHog's
      // default History API patching — more reliable with Next.js App
      // Router's client-side navigation than the library's built-in
      // auto-capture, which was written before App Router existed.
      capture_pageview: false,
      person_profiles: "identified_only", // don't create a person profile (and cost) for anonymous pre-signup visits
    });
  }, []);

  return <PHProvider client={posthog}>{children}</PHProvider>;
}

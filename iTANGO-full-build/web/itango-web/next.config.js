/** @type {import('next').NextConfig} */
const { withSentryConfig } = require("@sentry/nextjs");

const nextConfig = {
  // Required for the Docker multi-stage build (devops/docker/Dockerfile.web)
  // to produce a minimal runtime image — without this, the Docker COPY of
  // .next/standalone would fail because Next.js wouldn't generate it.
  output: "standalone",

  images: {
    // Supabase Storage-hosted images (event covers, avatars). Add the real
    // project ref's storage domain here once the Supabase project exists —
    // left as a placeholder pattern rather than wildcarding all hosts,
    // which would be an open image-proxy security issue.
    remotePatterns: [
      {
        protocol: "https",
        hostname: "*.supabase.co",
        pathname: "/storage/v1/object/public/**",
      },
    ],
  },
};

// withSentryConfig uploads source maps at build time (so stack traces in
// Sentry show real source, not minified bundles) and wraps API routes for
// automatic error capture. Requires SENTRY_AUTH_TOKEN, SENTRY_ORG,
// SENTRY_PROJECT as build-time env vars in CI — build succeeds without
// them, just skips source map upload, so this never blocks a build that
// hasn't configured Sentry yet.
module.exports = withSentryConfig(nextConfig, {
  silent: true,
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
});


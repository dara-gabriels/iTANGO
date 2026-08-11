// src/app/api/health/route.ts
//
// Deliberately does NOT check database connectivity — a health check that
// depends on Supabase being reachable means a transient Supabase blip marks
// every container instance unhealthy simultaneously, which would trigger
// the orchestrator (Fly/Kubernetes) to kill and restart every instance at
// once, making an upstream outage worse. This endpoint only confirms the
// Node process itself is alive and serving requests; upstream dependency
// health is Sentry/monitoring's job, not the container orchestrator's.
import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({ status: "ok", timestamp: new Date().toISOString() });
}

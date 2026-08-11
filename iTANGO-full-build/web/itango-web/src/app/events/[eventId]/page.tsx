// src/app/events/[eventId]/page.tsx
//
// Server Component — deliberately NOT "use client". This is the one screen
// category (per Master Program Plan §3 / §6) that MUST be server-rendered:
// public event pages are how iTANGO gets organic traffic from search and
// shared links. A client-only SPA render here would mean an empty <div>
// for search crawlers and social-media link unfurlers.

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import type { Metadata } from "next";

interface EventPageProps {
  params: { eventId: string };
}

async function getEvent(eventId: string) {
  const supabase = createSupabaseServerClient();
  // RLS on `events` (migration 010) already restricts this to
  // visibility = 'public' rows for an unauthenticated/anon request —
  // no need to duplicate that filter here.
  const { data, error } = await supabase
    .from("events")
    .select("id, title, description, cover_url, start_time, event_type, live_attendee_count, venues(name, city)")
    .eq("id", eventId)
    .single();

  if (error || !data) return null;
  return data;
}

export async function generateMetadata({ params }: EventPageProps): Promise<Metadata> {
  const event = await getEvent(params.eventId);
  if (!event) return { title: "Event not found — iTANGO" };

  return {
    title: `${event.title} — iTANGO`,
    description: event.description ?? `Join ${event.title} on iTANGO.`,
    openGraph: {
      title: event.title,
      description: event.description ?? undefined,
      images: event.cover_url ? [event.cover_url] : undefined,
    },
  };
}

export default async function EventPage({ params }: EventPageProps) {
  const event = await getEvent(params.eventId);
  if (!event) notFound();

  const venue = event.venues as unknown as { name: string; city: string } | null;

  return (
    <main className="max-w-2xl mx-auto px-6 py-10">
      {event.cover_url && (
        // eslint-disable-next-line @next/next/no-img-element -- next/image requires
        // a configured remote pattern for Supabase Storage; using <img> here keeps
        // the scaffold runnable without that config step. Swap to next/image once
        // the Storage domain is added to next.config.js remotePatterns.
        <img src={event.cover_url} alt={event.title} className="w-full rounded-2xl mb-6 object-cover" />
      )}
      <span className="badge-live">LIVE</span>
      <h1 className="font-wordmark text-h1 mt-3 mb-2">{event.title}</h1>
      {venue && (
        <p className="text-text-secondary mb-4">{venue.name} · {venue.city}</p>
      )}
      <p className="text-body text-text-secondary mb-6">{event.description}</p>
      <p className="text-body-sm text-text-tertiary mb-8">
        {event.live_attendee_count} people checked in right now
      </p>
      <button className="btn-gradient-primary px-8 py-3">Get Tickets</button>
    </main>
  );
}

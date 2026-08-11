// src/app/organizer/events/new/page.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

const EVENT_TYPES = ["party", "concert", "hangout", "private_party", "festival", "sports", "other"];
const VISIBILITY_OPTIONS = ["public", "friends_only", "invite_only"];

export default function CreateEventPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [eventType, setEventType] = useState("party");
  const [visibility, setVisibility] = useState("public");
  const [startTime, setStartTime] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!title.trim() || !startTime) {
      setError("Title and start time are required.");
      return;
    }

    setSubmitting(true);

    // Calls the Phase 5 Edge Function rather than a direct table insert —
    // it validates start_time is in the future and that venue_id (when
    // supplied) actually exists, logic that belongs in application code,
    // not duplicated as ad-hoc client-side checks (see backend/README.md
    // "Why so few functions are thin CRUD").
    const { data: sessionData } = await supabase.auth.getSession();
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/events`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${sessionData.session?.access_token}`,
        },
        body: JSON.stringify({
          title,
          description,
          event_type: eventType,
          visibility,
          start_time: new Date(startTime).toISOString(),
        }),
      },
    );

    setSubmitting(false);

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.message ?? "Couldn't create the event. Please try again.");
      return;
    }

    const event = await response.json();
    router.push(`/organizer/events/${event.id}`);
  }

  return (
    <div className="max-w-lg">
      <h1 className="text-h1 mb-6">Create Event</h1>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Field label="Event Name">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g., Neon Nights 2025"
            className="w-full bg-bg-elevated rounded-md px-4 py-3 outline-none focus:ring-2 focus:ring-brand-primary"
          />
        </Field>

        <Field label="Description">
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={4}
            className="w-full bg-bg-elevated rounded-md px-4 py-3 outline-none focus:ring-2 focus:ring-brand-primary resize-none"
          />
        </Field>

        <Field label="Event Type">
          <div className="flex flex-wrap gap-2">
            {EVENT_TYPES.map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => setEventType(type)}
                className={
                  eventType === type
                    ? "btn-gradient-primary px-4 py-2 text-body-sm capitalize"
                    : "bg-bg-elevated rounded-pill px-4 py-2 text-body-sm text-text-secondary capitalize"
                }
              >
                {type.replace("_", " ")}
              </button>
            ))}
          </div>
        </Field>

        <Field label="Visibility">
          <div className="flex gap-2">
            {VISIBILITY_OPTIONS.map((v) => (
              <button
                key={v}
                type="button"
                onClick={() => setVisibility(v)}
                className={
                  visibility === v
                    ? "btn-gradient-primary px-4 py-2 text-body-sm capitalize"
                    : "bg-bg-elevated rounded-pill px-4 py-2 text-body-sm text-text-secondary capitalize"
                }
              >
                {v.replace("_", " ")}
              </button>
            ))}
          </div>
        </Field>

        <Field label="Start Date & Time">
          <input
            type="datetime-local"
            value={startTime}
            onChange={(e) => setStartTime(e.target.value)}
            className="w-full bg-bg-elevated rounded-md px-4 py-3 outline-none focus:ring-2 focus:ring-brand-primary"
          />
        </Field>

        {error && <p className="text-status-danger text-body-sm">{error}</p>}

        <button type="submit" disabled={submitting} className="btn-gradient-primary w-full py-3 disabled:opacity-60">
          {submitting ? "Creating…" : "Create Event"}
        </button>

        <p className="text-text-tertiary text-caption">
          Your event is created as a draft. Add ticket types and publish it from the event page next.
        </p>
      </form>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="text-label uppercase text-text-secondary mb-2 block">{label}</label>
      {children}
    </div>
  );
}

// src/app/organizer/events/[eventId]/publish-button.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function PublishButton({ eventId, status }: { eventId: string; status: string }) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (status !== "draft") return null; // already published/pending/live/ended/cancelled — nothing to do here

  async function handlePublish() {
    setSubmitting(true);
    setError(null);

    // Calls the publish_event() Postgres function (migration 016) rather
    // than updating events.status directly — that function is the single
    // place the self-publish-vs-admin-approval decision is enforced, per
    // the platform_settings toggle. This button doesn't need to know which
    // mode is active; it just calls "publish" and shows whatever the
    // function actually did with the status.
    const { data: newStatus, error: rpcError } = await supabase.rpc("publish_event", { p_event_id: eventId });

    setSubmitting(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }

    router.refresh();

    if (newStatus === "pending_review") {
      window.alert("Submitted for review. Your event will go live once an admin approves it.");
    }
  }

  return (
    <div>
      <button onClick={handlePublish} disabled={submitting} className="btn-gradient-primary px-6 py-2.5 disabled:opacity-60">
        {submitting ? "Publishing…" : "Publish Event"}
      </button>
      {error && <p className="text-status-danger text-body-sm mt-2">{error}</p>}
    </div>
  );
}

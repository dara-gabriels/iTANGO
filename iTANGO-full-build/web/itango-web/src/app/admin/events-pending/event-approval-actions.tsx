// src/app/admin/events-pending/event-approval-actions.tsx
"use client";
/// <reference types="react" />
/** @jsxRuntime classic */
import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function EventApprovalActions({ eventId }: { eventId: string }) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();
  const [submitting, setSubmitting] = useState(false);

  async function handleApprove() {
    setSubmitting(true);
    const { error } = await supabase.rpc("approve_event", { p_event_id: eventId });
    setSubmitting(false);
    if (error) {
      window.alert("Could not approve: " + error.message);
      return;
    }
    router.refresh();
  }

  async function handleReject() {
    const reason = window.prompt("Reason for rejection (sent to the organizer, logged in audit trail):");
    if (!reason) return;

    setSubmitting(true);
    const { error } = await supabase.rpc("reject_event", { p_event_id: eventId, p_reason: reason });
    setSubmitting(false);
    if (error) {
      window.alert("Could not reject: " + error.message);
      return;
    }
    router.refresh();
  }

  return (
    <div className="flex gap-2">
      <button onClick={handleApprove} disabled={submitting} className="btn-gradient-primary px-4 py-2 text-body-sm disabled:opacity-50">
        Approve
      </button>
      <button onClick={handleReject} disabled={submitting} className="chip-danger rounded-pill px-4 py-2 text-body-sm disabled:opacity-50">
        Reject
      </button>
    </div>
  );
}

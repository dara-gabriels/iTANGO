// src/app/admin/events-pending/page.tsx
import React from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { EventApprovalActions } from "./event-approval-actions";

interface PendingEventRow {
  id: string;
  title: string;
  description: string | null;
  start_time: string;
  cover_url: string | null;
  organizer: { username: string } | null;
}

async function getPendingEvents(): Promise<PendingEventRow[]> {
  const supabase = createSupabaseServerClient();
  const { data, error } = await supabase
    .from("events")
    .select("id, title, description, start_time, cover_url, organizer:profiles!organizer_id(username)")
    .eq("status", "pending_review")
    .order("created_at", { ascending: true });

  if (error) {
    console.error("Failed to load pending events:", error);
    return [];
  }
  return data as unknown as PendingEventRow[];
}

async function getApprovalSetting(): Promise<boolean> {
  const supabase = createSupabaseServerClient();
  const { data } = await supabase.from("platform_settings").select("value").eq("key", "events_require_admin_approval").single();
  return data?.value === true;
}

export default async function PendingEventsPage() {
  const [events, approvalRequired] = await Promise.all([getPendingEvents(), getApprovalSetting()]);

  return (
    <div>
      <h1 className="text-h1 mb-2">Pending Events</h1>

      {!approvalRequired && (
        <div className="banner-warning p-4 mb-6">
          <p className="text-body-sm">
            <strong>Approval is currently OFF</strong> — organizers self-publish, so this queue should normally be
            empty. It only shows events submitted while approval was previously required. Toggle{" "}
            <code>events_require_admin_approval</code> in <code>platform_settings</code> to turn approval back on.
          </p>
        </div>
      )}

      {events.length === 0 ? (
        <p className="text-text-secondary py-12 text-center">No events awaiting review.</p>
      ) : (
        <div className="space-y-3">
          {events.map((event) => (
            <div key={event.id} className="bg-bg-surface rounded-xl p-4">
              <div className="flex items-start justify-between mb-2">
                <div>
                  <p className="font-semibold">{event.title}</p>
                  <p className="text-text-secondary text-body-sm">
                    by @{event.organizer?.username ?? "unknown"} ·{" "}
                    {new Date(event.start_time).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" })}
                  </p>
                </div>
              </div>
              {event.description && <p className="text-text-secondary text-body-sm mb-3">{event.description}</p>}
              <EventApprovalActions eventId={event.id} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

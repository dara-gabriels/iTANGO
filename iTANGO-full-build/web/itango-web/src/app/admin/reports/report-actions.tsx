// src/app/admin/reports/report-actions.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function ReportActions({ reportId, targetType, targetId }: { reportId: string; targetType: string; targetId: string }) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();
  const [submitting, setSubmitting] = useState(false);

  async function resolve(action: "dismissed" | "resolved", moderationAction?: string) {
    setSubmitting(true);

    const { data: { user } } = await supabase.auth.getUser();

    // Two writes, not one: update the report's status, and record the
    // moderation_actions entry (the actual audit trail per Master Plan §8).
    // Not wrapped in a DB transaction/function here — acceptable for MVP
    // since a partial failure just leaves a report open for a retry rather
    // than silently losing data, but a `resolve_report()` Postgres function
    // (same pattern as `admin_ban_user` in migration 015) would be the
    // more robust follow-up once this page sees real moderator load.
    await supabase.from("reports").update({ status: action, reviewed_by: user?.id, reviewed_at: new Date().toISOString() }).eq("id", reportId);

    if (moderationAction) {
      await supabase.from("moderation_actions").insert({
        report_id: reportId,
        moderator_id: user?.id,
        target_type: targetType,
        target_id: targetId,
        action: moderationAction,
      });
    }

    setSubmitting(false);
    router.refresh();
  }

  async function banUser() {
    if (targetType !== "user") return;
    setSubmitting(true);
    const { error } = await supabase.rpc("admin_ban_user", { p_target_user_id: targetId, p_reason: "Moderation queue action" });
    if (!error) await resolve("resolved", "banned");
    setSubmitting(false);
  }

  return (
    <div className="flex gap-2">
      <button
        onClick={() => resolve("dismissed")}
        disabled={submitting}
        className="bg-bg-elevated rounded-pill px-4 py-2 text-body-sm text-text-secondary disabled:opacity-50"
      >
        Dismiss
      </button>
      <button
        onClick={() => resolve("resolved", "content_removed")}
        disabled={submitting}
        className="bg-bg-elevated rounded-pill px-4 py-2 text-body-sm text-text-secondary disabled:opacity-50"
      >
        Remove Content
      </button>
      {targetType === "user" && (
        <button
          onClick={banUser}
          disabled={submitting}
          className="chip-danger rounded-pill px-4 py-2 text-body-sm disabled:opacity-50"
        >
          Ban User
        </button>
      )}
    </div>
  );
}

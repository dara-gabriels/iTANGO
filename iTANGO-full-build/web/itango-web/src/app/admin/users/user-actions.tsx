// src/app/admin/users/user-actions.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function UserActions({ userId, isBanned }: { userId: string; isBanned: boolean }) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();
  const [submitting, setSubmitting] = useState(false);

  async function handleBan() {
    const reason = window.prompt("Reason for ban (visible in audit log):");
    if (!reason) return;

    setSubmitting(true);
    // Calls the admin_ban_user() Postgres function (migration 015) rather
    // than updating profiles.is_banned directly — that function is what
    // writes the audit_logs entry atomically with the ban, and enforces
    // the admin/moderator role check server-side even if this button were
    // somehow reachable by someone without the role (defense in depth
    // beyond the layout-level redirect).
    const { error } = await supabase.rpc("admin_ban_user", { p_target_user_id: userId, p_reason: reason });
    setSubmitting(false);
    if (error) {
      window.alert("Could not ban user: " + error.message);
      return;
    }
    router.refresh();
  }

  async function handleUnban() {
    setSubmitting(true);
    const { error } = await supabase.rpc("admin_unban_user", { p_target_user_id: userId });
    setSubmitting(false);
    if (error) {
      window.alert("Could not unban user: " + error.message);
      return;
    }
    router.refresh();
  }

  return isBanned ? (
    <button
      onClick={handleUnban}
      disabled={submitting}
      className="bg-bg-elevated rounded-pill px-4 py-2 text-body-sm text-text-secondary disabled:opacity-50"
    >
      Unban
    </button>
  ) : (
    <button
      onClick={handleBan}
      disabled={submitting}
      className="chip-danger rounded-pill px-4 py-2 text-body-sm disabled:opacity-50"
    >
      Ban
    </button>
  );
}

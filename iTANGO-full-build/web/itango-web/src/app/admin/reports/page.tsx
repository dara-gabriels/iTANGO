// src/app/admin/reports/page.tsx
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ReportActions } from "./report-actions";

interface ReportRow {
  id: string;
  target_type: string;
  target_id: string;
  reason: string;
  details: string | null;
  status: string;
  created_at: string;
  reporter: { username: string } | null;
}

async function getOpenReports(): Promise<ReportRow[]> {
  const supabase = createSupabaseServerClient();
  // RLS policy `reports_select_own_or_mod` (migration 010) already scopes
  // this to moderators/admins seeing all reports; a non-mod caller would
  // get only their own reports back, not an error — the layout's role gate
  // is what actually keeps non-mods off this page.
  const { data, error } = await supabase
    .from("reports")
    .select("id, target_type, target_id, reason, details, status, created_at, reporter:profiles!reporter_id(username)")
    .eq("status", "open")
    .order("created_at", { ascending: true }); // oldest first — first-in-first-out queue

  if (error) {
    console.error("Failed to load reports:", error);
    return [];
  }
  return data as unknown as ReportRow[];
}

export default async function ModerationQueuePage() {
  const reports = await getOpenReports();

  return (
    <div>
      <h1 className="text-h1 mb-2">Moderation Queue</h1>
      <p className="text-text-secondary text-body-sm mb-6">{reports.length} open report{reports.length === 1 ? "" : "s"}</p>

      {reports.length === 0 ? (
        <p className="text-text-secondary py-12 text-center">Queue is clear. 🎉</p>
      ) : (
        <div className="space-y-3">
          {reports.map((report) => (
            <div key={report.id} className="bg-bg-surface rounded-xl p-4">
              <div className="flex items-start justify-between mb-2">
                <div>
                  <span className="text-caption uppercase text-status-warning font-semibold">{report.target_type}</span>
                  <p className="font-semibold">{report.reason}</p>
                </div>
                <span className="text-text-tertiary text-caption">
                  {new Date(report.created_at).toLocaleDateString("en-NG", { dateStyle: "medium" })}
                </span>
              </div>
              {report.details && <p className="text-text-secondary text-body-sm mb-2">{report.details}</p>}
              <p className="text-text-tertiary text-caption mb-3">
                Reported by @{report.reporter?.username ?? "unknown"} · target ID: {report.target_id}
              </p>
              <ReportActions reportId={report.id} targetType={report.target_type} targetId={report.target_id} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

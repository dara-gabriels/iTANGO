// src/app/admin/users/page.tsx
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { UserActions } from "./user-actions";

interface UserRow {
  id: string;
  username: string;
  display_name: string;
  is_verified: boolean;
  is_banned: boolean;
  banned_reason: string | null;
  energy_score: number;
  created_at: string;
}

async function getRecentUsers(searchQuery?: string): Promise<UserRow[]> {
  const supabase = createSupabaseServerClient();

  let query = supabase
    .from("profiles")
    .select("id, username, display_name, is_verified, is_banned, banned_reason, energy_score, created_at")
    .order("created_at", { ascending: false })
    .limit(50);

  if (searchQuery) {
    query = query.ilike("username", `%${searchQuery}%`);
  }

  const { data, error } = await query;
  if (error) {
    console.error("Failed to load users:", error);
    return [];
  }
  return data as UserRow[];
}

export default async function AdminUsersPage({ searchParams }: { searchParams: { q?: string } }) {
  const users = await getRecentUsers(searchParams.q);

  return (
    <div>
      <h1 className="text-h1 mb-6">Users</h1>

      <form className="mb-6">
        <input
          type="text"
          name="q"
          defaultValue={searchParams.q}
          placeholder="Search by username..."
          className="w-full max-w-sm bg-bg-elevated rounded-md px-4 py-2.5 outline-none focus:ring-2 focus:ring-brand-primary"
        />
      </form>

      <div className="space-y-2">
        {users.map((user) => (
          <div key={user.id} className="flex items-center justify-between bg-bg-surface rounded-xl p-4">
            <div>
              <div className="flex items-center gap-2">
                <p className="font-semibold">@{user.username}</p>
                {user.is_verified && <span className="text-accent-cyan text-caption">✓ verified</span>}
                {user.is_banned && <span className="text-status-danger text-caption font-semibold">BANNED</span>}
              </div>
              <p className="text-text-secondary text-body-sm">
                {user.display_name} · ⚡ {user.energy_score} · joined {new Date(user.created_at).toLocaleDateString("en-NG", { dateStyle: "medium" })}
              </p>
              {user.is_banned && user.banned_reason && (
                <p className="text-status-danger text-caption mt-1">Reason: {user.banned_reason}</p>
              )}
            </div>
            <UserActions userId={user.id} isBanned={user.is_banned} />
          </div>
        ))}
      </div>
    </div>
  );
}

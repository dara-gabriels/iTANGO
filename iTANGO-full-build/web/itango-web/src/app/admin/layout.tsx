// src/app/admin/layout.tsx
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

async function requireAdminOrModerator() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // Uses the same `has_role` helper the database's own RLS policies rely on
  // (migration 009), called here via RPC so the web layer's access check
  // and the database's enforcement check are never two different sources
  // of truth — if this ever said "yes" while RLS said "no," every admin
  // page would render empty tables instead of failing loudly, which is a
  // worse failure mode than just checking role once, consistently, here.
  const { data: isAdmin } = await supabase.rpc("has_role", { p_user_id: user.id, p_role: "admin" });
  const { data: isModerator } = await supabase.rpc("has_role", { p_user_id: user.id, p_role: "moderator" });

  if (!isAdmin && !isModerator) redirect("/home");
  return { isAdmin: Boolean(isAdmin) };
}

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { isAdmin } = await requireAdminOrModerator();

  return (
    <div className="min-h-screen">
      <header className="border-b border-border-subtle px-6 py-4 flex items-center justify-between">
        <Link href="/admin/reports" className="font-wordmark text-h2">
          iTango <span className="text-text-secondary text-body font-sans">Admin</span>
        </Link>
        <nav className="flex gap-6 text-body-sm text-text-secondary">
          <Link href="/admin/reports" className="hover:text-text-primary">Moderation Queue</Link>
          <Link href="/admin/events-pending" className="hover:text-text-primary">Pending Events</Link>
          {isAdmin && <Link href="/admin/users" className="hover:text-text-primary">Users</Link>}
        </nav>
      </header>
      <main className="max-w-5xl mx-auto px-6 py-8">{children}</main>
    </div>
  );
}

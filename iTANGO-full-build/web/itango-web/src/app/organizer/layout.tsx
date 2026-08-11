// src/app/organizer/layout.tsx
import Link from "next/link";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function OrganizerLayout({ children }: { children: React.ReactNode }) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  return (
    <div className="min-h-screen">
      <header className="border-b border-border-subtle px-6 py-4 flex items-center justify-between">
        <Link href="/organizer/events" className="font-wordmark text-h2">
          iTango <span className="text-text-secondary text-body font-sans">Organizer</span>
        </Link>
        <nav className="flex gap-6 text-body-sm text-text-secondary">
          <Link href="/organizer/events" className="hover:text-text-primary">Events</Link>
          <Link href="/organizer/events/new" className="hover:text-text-primary">Create Event</Link>
        </nav>
      </header>
      <main className="max-w-5xl mx-auto px-6 py-8">{children}</main>
    </div>
  );
}

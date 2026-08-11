// src/app/organizer/events/page.tsx
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";

interface OrganizerEventRow {
  id: string;
  title: string;
  status: string;
  start_time: string;
  cover_url: string | null;
  live_attendee_count: number;
  tickets: { quantity_sold: number; price: number; currency: string }[];
}

async function getOrganizerEvents() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  // RLS policy `events_update_own_or_admin` / the organizer_id column
  // already scopes this to the caller's own events even without the
  // explicit .eq() below — kept explicit here for readability, since this
  // query is the one an organizer trusts to show *only* their own numbers.
  const { data, error } = await supabase
    .from("events")
    .select("id, title, status, start_time, cover_url, live_attendee_count, tickets(quantity_sold, price, currency)")
    .eq("organizer_id", user.id)
    .order("start_time", { ascending: false });

  if (error) {
    console.error("Failed to load organizer events:", error);
    return [];
  }
  return data as OrganizerEventRow[];
}

function calculateRevenue(tickets: OrganizerEventRow["tickets"]): { amount: number; currency: string } {
  if (tickets.length === 0) return { amount: 0, currency: "NGN" };
  const amount = tickets.reduce((sum, t) => sum + t.quantity_sold * t.price, 0);
  return { amount, currency: tickets[0].currency };
}

export default async function OrganizerEventsPage() {
  const events = await getOrganizerEvents();

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-h1">My Events</h1>
        <Link href="/organizer/events/new" className="btn-gradient-primary px-5 py-2.5 text-body-sm">
          + Create Event
        </Link>
      </div>

      {events.length === 0 ? (
        <div className="text-center py-20 text-text-secondary">
          <p className="mb-4">You haven&apos;t created any events yet.</p>
          <Link href="/organizer/events/new" className="btn-gradient-primary px-6 py-3 inline-block">
            Create your first event
          </Link>
        </div>
      ) : (
        <div className="grid gap-4">
          {events.map((event) => {
            const revenue = calculateRevenue(event.tickets);
            const totalSold = event.tickets.reduce((sum, t) => sum + t.quantity_sold, 0);

            return (
              <Link
                key={event.id}
                href={`/organizer/events/${event.id}`}
                className="flex items-center gap-4 bg-bg-surface rounded-2xl p-4 hover:bg-bg-elevated transition-colors"
              >
                <div className="w-20 h-20 rounded-lg bg-bg-elevated flex-shrink-0 overflow-hidden">
                  {event.cover_url && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={event.cover_url} alt={event.title} className="w-full h-full object-cover" />
                  )}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <h2 className="font-semibold">{event.title}</h2>
                    <StatusBadge status={event.status} />
                  </div>
                  <p className="text-text-secondary text-body-sm">
                    {new Date(event.start_time).toLocaleDateString("en-NG", { dateStyle: "medium" })}
                    {" · "}
                    {event.live_attendee_count} checked in
                  </p>
                </div>
                <div className="text-right">
                  <p className="font-semibold">{revenue.currency} {revenue.amount.toLocaleString()}</p>
                  <p className="text-text-secondary text-body-sm">{totalSold} tickets sold</p>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const colorClass = status === "live" ? "text-status-live" : status === "published" ? "text-accent-emerald" : "text-text-tertiary";
  return <span className={`text-caption uppercase font-semibold ${colorClass}`}>{status}</span>;
}

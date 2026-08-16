// src/app/organizer/events/[eventId]/page.tsx
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { PublishButton } from "./publish-button";
import { AddTicketsForm } from "./add-tickets-form";

interface EventPageProps {
  params: { eventId: string };
}

async function getOrganizerEvent(eventId: string, userId: string) {
  const supabase = createSupabaseServerClient();

  const { data: event, error } = await supabase
    .from("events")
    .select("id, title, description, status, start_time, live_attendee_count, organizer_id, tickets(id, name, ticket_type, price, currency, quantity_total, quantity_sold)")
    .eq("id", eventId)
    .single();

  if (error || !event) return null;
  if (event.organizer_id !== userId) return null;

  return event;
}

export default async function OrganizerEventDetailPage({ params }: EventPageProps) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) notFound();

  const event = await getOrganizerEvent(params.eventId, user.id);
  if (!event) notFound();

  const totalRevenue = event.tickets.reduce((sum, t) => sum + t.quantity_sold * t.price, 0);
  const totalSold = event.tickets.reduce((sum, t) => sum + t.quantity_sold, 0);
  const currency = event.tickets[0]?.currency ?? "NGN";

  return (
    <div>
      <Link href="/organizer/events" className="text-text-secondary text-body-sm mb-4 inline-block">
        ← Back to My Events
      </Link>

      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-h1">{event.title}</h1>
          <p className="text-text-secondary text-body-sm capitalize">{event.status.replace("_", " ")} · {new Date(event.start_time).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" })}</p>
        </div>
        <PublishButton eventId={event.id} status={event.status} />
      </div>

      <Link
        href={`/organizer/events/${event.id}/checkin`}
        className="inline-block mb-8 bg-bg-elevated rounded-pill px-5 py-2.5 text-body-sm hover:bg-bg-surface"
      >
        📷 Open Door Check-In Scanner
      </Link>

      <div className="grid grid-cols-3 gap-4 mb-8">
        <StatCard label="Tickets Sold" value={totalSold.toString()} />
        <StatCard label="Revenue" value={`${currency} ${totalRevenue.toLocaleString()}`} />
        <StatCard label="Checked In" value={event.live_attendee_count.toString()} />
      </div>

      <h2 className="text-h2 mb-4">Manage Ticketing</h2>
      
      {/* Dynamic Ticket Input Form Engine */}
      <AddTicketsForm eventId={event.id} />

      <h2 className="text-h2 mb-4 mt-8">Active Ticket Tiers</h2>
      {event.tickets.length === 0 ? (
        <p className="text-text-secondary mb-6">
          No ticket types added yet. Use the tool configuration panel above to create your first pricing tier.
        </p>
      ) : (
        <div className="space-y-3">
          {event.tickets.map((ticket) => (
            <div key={ticket.id} className="flex items-center justify-between bg-bg-surface rounded-xl p-4">
              <div>
                <p className="font-semibold capitalize">{ticket.name}</p>
                <p className="text-text-secondary text-body-sm capitalize">{ticket.ticket_type.replace("_", " ")}</p>
              </div>
              <div className="text-right">
                <p className="font-semibold">{ticket.currency} {ticket.price.toLocaleString()}</p>
                <p className="text-text-secondary text-body-sm">
                  {ticket.quantity_sold} / {ticket.quantity_total} sold
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-bg-surface rounded-xl p-4">
      <p className="text-text-secondary text-body-sm mb-1">{label}</p>
      <p className="text-h2">{value}</p>
    </div>
  );
}

"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

interface AddTicketsFormProps {
  eventId: string;
}

export function AddTicketsForm({ eventId }: AddTicketsFormProps) {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [capacity, setCapacity] = useState("");
  const [ticketType, setTicketType] = useState("regular");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!name.trim() || !price || !capacity) {
      setError("All fields are required.");
      return;
    }

    setSubmitting(true);

    // Call the correct database relation backend target name
    const { error: insertError } = await supabase
      .from("ticket_types")
      .insert({
        event_id: eventId,
        name: name.trim(),
        ticket_type: ticketType,
        price: parseFloat(price),
        currency: "NGN",
        quantity_total: parseInt(capacity, 10),
        quantity_sold: 0
      });

    setSubmitting(false);

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setName("");
    setPrice("");
    setCapacity("");
    router.refresh();
  }

  return (
    <form onSubmit={handleAdd} className="bg-bg-surface rounded-xl p-5 border border-slate-800 space-y-4 my-6">
      <h3 className="text-body font-semibold text-white">Create Ticket Tier</h3>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="text-caption text-text-secondary block mb-1">Tier Name</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="VIP Table, Early Bird..."
            className="w-full bg-bg-elevated rounded-md px-3 py-2 text-white outline-none focus:ring-1 focus:ring-brand-primary text-sm"
          />
        </div>

        <div>
          <label className="text-caption text-text-secondary block mb-1">Type</label>
          <select
            value={ticketType}
            onChange={(e) => setTicketType(e.target.value)}
            className="w-full bg-bg-elevated rounded-md px-3 py-2 text-white outline-none focus:ring-1 focus:ring-brand-primary text-sm"
          >
            <option value="regular">Regular Pass</option>
            <option value="vip">VIP Entry</option>
            <option value="table">Table Booking</option>
          </select>
        </div>

        <div>
          <label className="text-caption text-text-secondary block mb-1">Price (NGN)</label>
          <input
            type="number"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            placeholder="5000"
            className="w-full bg-bg-elevated rounded-md px-3 py-2 text-white outline-none focus:ring-1 focus:ring-brand-primary text-sm"
          />
        </div>

        <div>
          <label className="text-caption text-text-secondary block mb-1">Max Availability</label>
          <input
            type="number"
            value={capacity}
            onChange={(e) => setCapacity(e.target.value)}
            placeholder="150"
            className="w-full bg-bg-elevated rounded-md px-3 py-2 text-white outline-none focus:ring-1 focus:ring-brand-primary text-sm"
          />
        </div>
      </div>

      {error && <p className="text-status-danger text-caption">{error}</p>}

      <button
        type="submit"
        disabled={submitting}
        className="btn-gradient-primary text-body-sm font-semibold px-4 py-2 w-full md:w-auto disabled:opacity-60"
      >
        {submitting ? "Adding..." : "+ Save Ticket Tier"}
      </button>
    </form>
  );
}

// src/app/organizer/events/[eventId]/checkin/page.tsx
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { QrScanner } from "./qr-scanner";

interface CheckInPageProps {
  params: { eventId: string };
}

export default async function StaffCheckInPage({ params }: CheckInPageProps) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) notFound();

  const { data: event, error } = await supabase
    .from("events")
    .select("id, title, organizer_id")
    .eq("id", params.eventId)
    .single();

  if (error || !event || event.organizer_id !== user.id) notFound();

  return (
    <div className="max-w-md mx-auto">
      <Link href={`/organizer/events/${params.eventId}`} className="text-text-secondary text-body-sm mb-4 inline-block">
        ← Back to {event.title}
      </Link>
      <h1 className="text-h1 mb-2">Door Check-In</h1>
      <p className="text-text-secondary text-body-sm mb-6">
        Point the camera at an attendee&apos;s ticket QR code. This checks them in immediately and unlocks the event&apos;s chat room for them.
      </p>
      <QrScanner />
    </div>
  );
}

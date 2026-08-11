// src/app/organizer/events/[eventId]/checkin/qr-scanner.tsx
"use client";

import { useEffect, useRef, useState } from "react";
import { Html5Qrcode } from "html5-qrcode";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

interface CheckInResult {
  status: "success" | "error";
  message: string;
  attendeeName?: string;
}

export function QrScanner() {
  const supabase = createSupabaseBrowserClient();
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const [isScanning, setIsScanning] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [lastResult, setLastResult] = useState<CheckInResult | null>(null);
  const [scanCount, setScanCount] = useState(0);

  useEffect(() => {
    return () => {
      // Camera access must be explicitly torn down on unmount — leaving it
      // running would keep the webcam light on after the organizer
      // navigates away, which is both a battery drain and a real privacy
      // bad-look for a check-in tool.
      scannerRef.current?.stop().catch(() => {});
    };
  }, []);

  async function startScanning() {
    setIsScanning(true);
    setLastResult(null);

    const scanner = new Html5Qrcode("qr-reader");
    scannerRef.current = scanner;

    try {
      await scanner.start(
        { facingMode: "environment" }, // rear camera — this is a door-staff tool, not a selfie
        { fps: 10, qrbox: { width: 250, height: 250 } },
        async (decodedText) => {
          // Pause scanning while we process this code — otherwise the same
          // QR held in frame fires this callback dozens of times per second.
          await scanner.pause(true);
          await handleScan(decodedText);
          await scanner.resume();
        },
        () => {
          // Per-frame "no QR found" callback — deliberately silent, this
          // fires continuously while the camera is pointed at anything
          // that isn't a QR code, which is most of the time.
        },
      );
    } catch (err) {
      setLastResult({ status: "error", message: "Could not access camera. Check browser permissions." });
      setIsScanning(false);
    }
  }

  async function stopScanning() {
    await scannerRef.current?.stop();
    setIsScanning(false);
  }

  async function handleScan(qrToken: string) {
    setProcessing(true);

    const { data: sessionData } = await supabase.auth.getSession();
    const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/staff-checkin`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${sessionData.session?.access_token}`,
      },
      body: JSON.stringify({ qr_token: qrToken }),
    });

    const body = await response.json();
    setProcessing(false);
    setScanCount((c) => c + 1);

    if (response.ok) {
      setLastResult({
        status: "success",
        message: "Checked in successfully",
        attendeeName: body.attendee?.display_name ?? body.attendee?.username,
      });
    } else {
      setLastResult({ status: "error", message: body.message ?? "Check-in failed" });
    }
  }

  return (
    <div>
      <div id="qr-reader" className="w-full max-w-sm mx-auto rounded-2xl overflow-hidden bg-bg-surface" />

      <div className="mt-6 flex flex-col items-center gap-4">
        {!isScanning ? (
          <button onClick={startScanning} className="btn-gradient-primary px-8 py-3">
            Start Scanning
          </button>
        ) : (
          <button onClick={stopScanning} className="bg-bg-elevated rounded-pill px-8 py-3 text-text-secondary">
            Stop Scanning
          </button>
        )}

        {processing && <p className="text-text-secondary text-body-sm">Verifying...</p>}

        {lastResult && (
          <div className={`w-full max-w-sm rounded-xl p-4 text-center ${lastResult.status === "success" ? "chip-success" : "chip-danger"}`}>
            <p className="font-semibold">{lastResult.status === "success" ? "✓ " : "✗ "}{lastResult.message}</p>
            {lastResult.attendeeName && <p className="text-body-sm mt-1">{lastResult.attendeeName}</p>}
          </div>
        )}

        <p className="text-text-tertiary text-caption">{scanCount} scan{scanCount === 1 ? "" : "s"} this session</p>
      </div>
    </div>
  );
}

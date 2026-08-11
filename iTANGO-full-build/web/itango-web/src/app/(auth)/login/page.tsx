// src/app/(auth)/login/page.tsx
"use client";

import React, { useState, ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

const PHONE_REGEX = /^\+[1-9]\d{7,14}$/;

export default function LoginPage() {
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  const [phone, setPhone] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSendOtp() {
    if (!PHONE_REGEX.test(phone)) {
      setError("Enter a valid phone number, e.g. +2348012345678");
      return;
    }
    setError(null);
    setLoading(true);
    const { error: otpError } = await supabase.auth.signInWithOtp({ phone });
    setLoading(false);
    if (otpError) {
      setError("Couldn't send the code — please try again.");
      return;
    }
    setOtpSent(true);
  }

  async function handleVerifyOtp() {
    setLoading(true);
    const { error: verifyError } = await supabase.auth.verifyOtp({
      phone,
      token: code,
      type: "sms",
    });
    setLoading(false);
    if (verifyError) {
      setError("That code didn't match. Check it and try again.");
      return;
    }
    router.push("/home");
  }

  return (
    <main className="min-h-screen flex flex-col justify-center px-6 max-w-md mx-auto">
      <h1 className="font-wordmark text-h1 mb-1">iTango</h1>
      <p className="text-text-secondary tracking-wide mb-10">Own the Night</p>

      {!otpSent ? (
        <>
          <label className="text-label uppercase text-text-secondary mb-2 block">Phone number</label>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+234 801 234 5678"
            className="w-full bg-bg-elevated rounded-md px-4 py-3 mb-2 outline-none focus:ring-2 focus:ring-brand-primary"
          />
          {error && <p className="text-status-danger text-body-sm mb-3">{error}</p>}
          <button
            onClick={handleSendOtp}
            disabled={loading}
            className="btn-gradient-primary w-full py-3 mt-2 disabled:opacity-60"
          >
            {loading ? "Sending…" : "Continue"}
          </button>
        </>
      ) : (
        <>
          <label className="text-label uppercase text-text-secondary mb-2 block">
            Enter the code sent to {phone}
          </label>
          <input
            type="text"
            inputMode="numeric"
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="••••••"
            className="w-full bg-bg-elevated rounded-md px-4 py-3 mb-2 text-center text-h2 tracking-[0.5em] outline-none focus:ring-2 focus:ring-brand-primary"
          />
          {error && <p className="text-status-danger text-body-sm mb-3">{error}</p>}
          <button
            onClick={handleVerifyOtp}
            disabled={loading}
            className="btn-gradient-primary w-full py-3 mt-2 disabled:opacity-60"
          >
            {loading ? "Verifying…" : "Verify"}
          </button>
          <button
            onClick={handleSendOtp}
            className="text-text-secondary text-body-sm mt-4 self-start"
          >
            Resend code
          </button>
        </>
      )}
    </main>
  );
}

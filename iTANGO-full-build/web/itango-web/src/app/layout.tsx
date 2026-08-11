// src/app/layout.tsx
import type { Metadata } from "next";
import { Inter, Playfair_Display } from "next/font/google";
import "./globals.css";
import { PostHogProvider } from "@/lib/analytics/posthog-provider";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const playfair = Playfair_Display({ subsets: ["latin"], variable: "--font-playfair" });

export const metadata: Metadata = {
  title: "iTANGO — Own the Night",
  description: "Discover nightlife, events, and experiences happening around you, right now.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="dark">
      <body className={`${inter.variable} ${playfair.variable} font-sans bg-bg-base text-text-primary`}>
        <PostHogProvider>{children}</PostHogProvider>
      </body>
    </html>
  );
}

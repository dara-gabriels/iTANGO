// tailwind.config.ts
// Generated from design-tokens.json — maps CSS variables (globals.css) into
// Tailwind utility classes so components can use e.g. bg-brand-primary,
// text-status-live, rounded-2xl, shadow-glow directly.

import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["selector", '[data-theme="dark"]'],
  content: ["./src/**/*.{ts,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        bg: {
          base: "var(--color-bg-base)",
          surface: "var(--color-bg-surface)",
          elevated: "var(--color-bg-surface-elevated)",
        },
        brand: {
          start: "var(--color-brand-gradient-start)",
          end: "var(--color-brand-gradient-end)",
          primary: "var(--color-brand-primary)",
        },
        accent: {
          cyan: "var(--color-accent-cyan)",
          amber: "var(--color-accent-amber)",
          emerald: "var(--color-accent-emerald)",
        },
        status: {
          live: "var(--color-status-live)",
          warmthHot: "var(--color-status-warmth-hot)",
          warmthWarm: "var(--color-status-warmth-warm)",
          success: "var(--color-status-success)",
          warning: "var(--color-status-warning)",
          danger: "var(--color-status-danger)",
          info: "var(--color-status-info)",
        },
        text: {
          primary: "var(--color-text-primary)",
          secondary: "var(--color-text-secondary)",
          tertiary: "var(--color-text-tertiary)",
          link: "var(--color-text-link)",
        },
        border: {
          subtle: "var(--color-border-subtle)",
          DEFAULT: "var(--color-border-default)",
        },
      },
      borderRadius: {
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
        lg: "var(--radius-lg)",
        xl: "var(--radius-xl)",
        "2xl": "var(--radius-2xl)",
        pill: "var(--radius-pill)",
      },
      boxShadow: {
        sm: "var(--shadow-sm)",
        md: "var(--shadow-md)",
        lg: "var(--shadow-lg)",
        glow: "var(--shadow-glow)",
      },
      backgroundImage: {
        "gradient-primary-cta": "var(--gradient-primary-cta)",
        "gradient-warmth-hot": "var(--gradient-warmth-hot)",
        "gradient-live-badge": "var(--gradient-live-badge)",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
      },
      fontSize: {
        display: ["30px", { lineHeight: "36px", fontWeight: "700", letterSpacing: "-0.5px" }],
        h1: ["24px", { lineHeight: "30px", fontWeight: "700", letterSpacing: "-0.25px" }],
        h2: ["20px", { lineHeight: "26px", fontWeight: "700" }],
        h3: ["17px", { lineHeight: "22px", fontWeight: "600" }],
        "body-lg": ["16px", { lineHeight: "22px", fontWeight: "400" }],
        body: ["14px", { lineHeight: "20px", fontWeight: "400" }],
        "body-sm": ["13px", { lineHeight: "18px", fontWeight: "400" }],
        label: ["12px", { lineHeight: "16px", fontWeight: "600", letterSpacing: "0.6px" }],
        caption: ["11px", { lineHeight: "14px", fontWeight: "500", letterSpacing: "0.2px" }],
      },
      transitionTimingFunction: {
        standard: "var(--ease-standard)",
        spring: "var(--ease-spring)",
      },
      transitionDuration: {
        fast: "120ms",
        base: "200ms",
        slow: "320ms",
      },
    },
  },
  plugins: [],
};

export default config;

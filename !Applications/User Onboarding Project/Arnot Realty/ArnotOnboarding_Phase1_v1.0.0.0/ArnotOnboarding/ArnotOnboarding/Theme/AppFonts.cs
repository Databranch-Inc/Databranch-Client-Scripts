// =============================================================
// ArnotOnboarding — AppFonts.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Central font definitions. Uses Segoe UI as the primary
//              sans-serif (closest Windows system match to IBM Plex Sans)
//              and Consolas for monospace/technical values.
// =============================================================

using System.Drawing;

namespace ArnotOnboarding.Theme
{
    public static class AppFonts
    {
        // ── Primary (Segoe UI) ─────────────────────────────────────
        public static readonly Font Heading1    = new Font("Segoe UI", 16f, FontStyle.Bold);
        public static readonly Font Heading2    = new Font("Segoe UI", 13f, FontStyle.Bold);
        public static readonly Font Heading3    = new Font("Segoe UI", 11f, FontStyle.Bold);
        public static readonly Font SectionLabel = new Font("Segoe UI", 9f, FontStyle.Bold);
        public static readonly Font Body        = new Font("Segoe UI", 10f, FontStyle.Regular);
        public static readonly Font BodySmall   = new Font("Segoe UI", 9f,  FontStyle.Regular);
        public static readonly Font Label       = new Font("Segoe UI", 9f,  FontStyle.Regular);
        public static readonly Font LabelBold   = new Font("Segoe UI", 9f,  FontStyle.Bold);
        public static readonly Font Button      = new Font("Segoe UI", 10f, FontStyle.Bold);
        public static readonly Font NavItem     = new Font("Segoe UI", 10f, FontStyle.Regular);
        public static readonly Font NavItemActive = new Font("Segoe UI", 10f, FontStyle.Bold);
        public static readonly Font Caption     = new Font("Segoe UI", 8.5f, FontStyle.Regular);
        public static readonly Font EyebrowLabel = new Font("Segoe UI", 8f, FontStyle.Bold);

        // ── Monospace (Consolas) — paths, ids, version numbers ─────
        public static readonly Font Mono        = new Font("Consolas", 9.5f, FontStyle.Regular);
        public static readonly Font MonoSmall   = new Font("Consolas", 8.5f, FontStyle.Regular);
        public static readonly Font MonoBold    = new Font("Consolas", 9.5f, FontStyle.Bold);
        public static readonly Font Version     = new Font("Consolas", 9f,   FontStyle.Regular);

        // ── Wizard step indicator ──────────────────────────────────
        public static readonly Font StepNum     = new Font("Segoe UI", 8f, FontStyle.Bold);
        public static readonly Font WizardTitle = new Font("Segoe UI", 14f, FontStyle.Bold);
        public static readonly Font WizardSubtitle = new Font("Segoe UI", 10f, FontStyle.Regular);

        // ── PDF only (embedded into PdfSharp rendering) ────────────
        // PdfSharp uses its own font loading; these constants define
        // the font names to request from the PDF engine.
        public const string PdfFontPrimary = "Helvetica";
        public const string PdfFontMono    = "Courier";
    }
}

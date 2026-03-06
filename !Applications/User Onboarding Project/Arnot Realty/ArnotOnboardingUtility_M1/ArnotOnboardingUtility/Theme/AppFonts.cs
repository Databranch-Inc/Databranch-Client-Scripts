// =============================================================
// ArnotOnboardingUtility — Theme/AppFonts.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Pre-instantiated font instances for the whole
//              application. NEVER use new Font() inline in
//              control factory methods — it leaks GDI handles.
//              Segoe UI = primary (IBM Plex Sans equivalent).
//              Consolas  = monospace / console output.
// =============================================================
using System.Drawing;

namespace ArnotOnboardingUtility.Theme
{
    public static class AppFonts
    {
        // ── Primary: Segoe UI ──────────────────────────────────────────
        public static readonly Font Heading1     = new Font("Segoe UI", 16f,  FontStyle.Bold);
        public static readonly Font Heading2     = new Font("Segoe UI", 13f,  FontStyle.Bold);
        public static readonly Font Heading3     = new Font("Segoe UI", 11f,  FontStyle.Bold);
        public static readonly Font BodyLarge    = new Font("Segoe UI", 11f,  FontStyle.Regular);
        public static readonly Font Body         = new Font("Segoe UI", 10f,  FontStyle.Regular);
        public static readonly Font BodyBold     = new Font("Segoe UI", 10f,  FontStyle.Bold);
        public static readonly Font BodySmall    = new Font("Segoe UI", 9f,   FontStyle.Regular);
        public static readonly Font Label        = new Font("Segoe UI", 9f,   FontStyle.Regular);
        public static readonly Font LabelBold    = new Font("Segoe UI", 9f,   FontStyle.Bold);
        public static readonly Font Caption      = new Font("Segoe UI", 8f,   FontStyle.Regular);
        public static readonly Font CaptionBold  = new Font("Segoe UI", 8f,   FontStyle.Bold);

        // ── Nav Rail ──────────────────────────────────────────────────
        public static readonly Font NavItem      = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        public static readonly Font NavItemBold  = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        public static readonly Font NavSection   = new Font("Segoe UI", 7.5f, FontStyle.Bold);
        public static readonly Font NavEyebrow   = new Font("Segoe UI", 8f,   FontStyle.Bold);
        public static readonly Font NavTitle     = new Font("Segoe UI", 10f,  FontStyle.Bold);
        public static readonly Font NavVersion   = new Font("Consolas",  8f,  FontStyle.Regular);

        // ── Buttons ───────────────────────────────────────────────────
        public static readonly Font Button       = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        public static readonly Font ButtonBold   = new Font("Segoe UI", 9.5f, FontStyle.Bold);

        // ── Step Cards (Milestone 2) ───────────────────────────────────
        public static readonly Font StepTitle    = new Font("Segoe UI", 11f,  FontStyle.Bold);
        public static readonly Font StepBody     = new Font("Segoe UI", 9.5f, FontStyle.Regular);
        public static readonly Font StepBadge    = new Font("Segoe UI", 7.5f, FontStyle.Bold);
        public static readonly Font StepDataLbl  = new Font("Segoe UI", 8.5f, FontStyle.Bold);
        public static readonly Font StepDataVal  = new Font("Segoe UI", 9f,   FontStyle.Regular);

        // ── Monospace: Consolas ───────────────────────────────────────
        public static readonly Font Mono         = new Font("Consolas", 9.5f, FontStyle.Regular);
        public static readonly Font MonoSmall    = new Font("Consolas", 8.5f, FontStyle.Regular);
        public static readonly Font MonoLarge    = new Font("Consolas", 11f,  FontStyle.Regular);
        public static readonly Font ConsoleFeed  = new Font("Consolas", 10f,  FontStyle.Regular);
    }
}

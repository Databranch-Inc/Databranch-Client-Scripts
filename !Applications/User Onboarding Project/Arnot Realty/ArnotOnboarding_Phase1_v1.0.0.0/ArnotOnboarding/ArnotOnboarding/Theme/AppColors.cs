// =============================================================
// ArnotOnboarding — AppColors.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Central color token definitions translated from the
//              Databranch UI Design System. All UI colors must
//              reference this class — no hardcoded hex values elsewhere.
// =============================================================

using System.Drawing;

namespace ArnotOnboarding.Theme
{
    /// <summary>
    /// Databranch Design System color tokens for WinForms.
    /// All values translated from Databranch_UIDesignSpec.html.
    /// </summary>
    public static class AppColors
    {
        // ── Brand ──────────────────────────────────────────────────
        public static readonly Color BrandRed       = ColorFromHex("#B01020");
        public static readonly Color BrandRedMuted  = ColorFromHex("#8B2030");
        public static readonly Color BrandRedSoft   = ColorFromHex("#C0404A"); // Primary action buttons, active nav
        public static readonly Color BrandRedPale   = ColorFromHex("#D07080"); // Section headings, secondary accents
        public static readonly Color BrandRedGlow   = Color.FromArgb(46, 176, 16, 32);

        public static readonly Color BrandBlue      = ColorFromHex("#2E8BFF"); // Interactive elements, links, focus
        public static readonly Color BrandBlueMid   = ColorFromHex("#1A6FD4"); // Pressed/active states
        public static readonly Color BrandBlueMuted = ColorFromHex("#2A5FA8"); // Secondary interactive
        public static readonly Color BrandBluePale  = ColorFromHex("#4A8FD4"); // Tags, badges
        public static readonly Color BrandBlueDim   = ColorFromHex("#1A3A6A"); // Deep panel backgrounds
        public static readonly Color BrandBlueGlow  = Color.FromArgb(38, 30, 144, 255);

        // ── Surface Layers (depth stack) ───────────────────────────
        public static readonly Color SurfaceVoid     = ColorFromHex("#080C14"); // Deepest background
        public static readonly Color SurfaceBase     = ColorFromHex("#0D1520"); // Main form background
        public static readonly Color SurfaceRaised   = ColorFromHex("#111C2E"); // Sidebar, nav panel
        public static readonly Color SurfaceCard     = ColorFromHex("#162238"); // Cards, group boxes
        public static readonly Color SurfaceElevated = ColorFromHex("#1D2E48"); // Hover, active panel
        public static readonly Color SurfaceOverlay  = ColorFromHex("#243558"); // Dialogs, selected states
        public static readonly Color SurfaceHigh     = ColorFromHex("#2C3F68"); // Badges, chips

        // ── Text ───────────────────────────────────────────────────
        public static readonly Color TextPrimary   = ColorFromHex("#F0F4FF"); // Headings, key labels
        public static readonly Color TextSecondary = ColorFromHex("#A8BDD8"); // Body text, field values
        public static readonly Color TextMuted     = ColorFromHex("#607090"); // Helper labels, metadata
        public static readonly Color TextDim       = ColorFromHex("#3A5070"); // Placeholders, disabled
        public static readonly Color TextInverse   = ColorFromHex("#080C14"); // Text on bright buttons

        // ── Borders ────────────────────────────────────────────────
        public static readonly Color BorderSubtle      = ColorFromHex("#1A2D48");
        public static readonly Color BorderDefault     = ColorFromHex("#213A58");
        public static readonly Color BorderMid         = ColorFromHex("#2A4A70");
        public static readonly Color BorderAccentBlue  = ColorFromHex("#1E6ABF");
        public static readonly Color BorderAccentRed   = ColorFromHex("#8B2030");

        // ── Status / Semantic ──────────────────────────────────────
        public static readonly Color StatusSuccess   = ColorFromHex("#22C55E");
        public static readonly Color StatusSuccessBg = ColorFromHex("#0A2818");
        public static readonly Color StatusSuccessBd = ColorFromHex("#1A5030");

        public static readonly Color StatusWarn      = ColorFromHex("#E8A020");
        public static readonly Color StatusWarnBg    = ColorFromHex("#1E1800");
        public static readonly Color StatusWarnBd    = ColorFromHex("#6A4800");

        public static readonly Color StatusError     = ColorFromHex("#C84040");
        public static readonly Color StatusErrorBg   = ColorFromHex("#200A0A");
        public static readonly Color StatusErrorBd   = ColorFromHex("#6A1818");

        public static readonly Color StatusInfo      = ColorFromHex("#2E8BFF");
        public static readonly Color StatusInfoBg    = ColorFromHex("#091828");
        public static readonly Color StatusInfoBd    = ColorFromHex("#1A3A6A");

        // ── Utility ────────────────────────────────────────────────
        /// <summary>Converts a CSS-style hex string (#RRGGBB) to a System.Drawing.Color.</summary>
        public static Color ColorFromHex(string hex)
        {
            hex = hex.TrimStart('#');
            return Color.FromArgb(
                System.Convert.ToInt32(hex.Substring(0, 2), 16),
                System.Convert.ToInt32(hex.Substring(2, 2), 16),
                System.Convert.ToInt32(hex.Substring(4, 2), 16)
            );
        }

        /// <summary>Returns a Color with modified alpha from an existing Color.</summary>
        public static Color WithAlpha(Color c, int alpha)
            => Color.FromArgb(alpha, c.R, c.G, c.B);
    }
}

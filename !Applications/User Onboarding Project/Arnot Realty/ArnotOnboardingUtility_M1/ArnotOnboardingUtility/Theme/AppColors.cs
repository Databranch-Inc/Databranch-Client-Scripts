// =============================================================
// ArnotOnboardingUtility — Theme/AppColors.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Databranch unified dark theme color tokens.
//              All Color values in the application must
//              reference this class — no hardcoded hex values.
//              Matches ArnotOnboarding v1.7 and UI Design Spec.
// =============================================================
using System.Drawing;

namespace ArnotOnboardingUtility.Theme
{
    public static class AppColors
    {
        // ── Surface Layer Stack ────────────────────────────────────────
        public static readonly Color SurfaceVoid     = ColorTranslator.FromHtml("#080C14");
        public static readonly Color SurfaceBase     = ColorTranslator.FromHtml("#0D1520");
        public static readonly Color SurfaceRaised   = ColorTranslator.FromHtml("#111C2E");
        public static readonly Color SurfaceCard     = ColorTranslator.FromHtml("#162238");
        public static readonly Color SurfaceElevated = ColorTranslator.FromHtml("#1D2E48");
        public static readonly Color SurfaceOverlay  = ColorTranslator.FromHtml("#243558");
        public static readonly Color SurfaceHigh     = ColorTranslator.FromHtml("#2C3F68");

        // ── Brand Red (identity anchor, active nav, primary buttons) ──
        public static readonly Color BrandRed        = ColorTranslator.FromHtml("#B01020");
        public static readonly Color BrandRedMuted   = ColorTranslator.FromHtml("#8B2030");
        public static readonly Color BrandRedSoft    = ColorTranslator.FromHtml("#C0404A");
        public static readonly Color BrandRedPale    = ColorTranslator.FromHtml("#D07080");

        // ── Brand Blue (interactive affordances, links, focus rings) ──
        public static readonly Color BrandBlue       = ColorTranslator.FromHtml("#2E8BFF");
        public static readonly Color BrandBlueMuted  = ColorTranslator.FromHtml("#2A5FA8");
        public static readonly Color BrandBluePale   = ColorTranslator.FromHtml("#4A8FD4");
        public static readonly Color BrandBlueDim    = ColorTranslator.FromHtml("#1A3A6A");

        // ── Text ───────────────────────────────────────────────────────
        public static readonly Color TextPrimary     = ColorTranslator.FromHtml("#F0F4FF");
        public static readonly Color TextSecondary   = ColorTranslator.FromHtml("#A8BDD8");
        public static readonly Color TextMuted       = ColorTranslator.FromHtml("#607090");
        public static readonly Color TextDim         = ColorTranslator.FromHtml("#3A5070");
        public static readonly Color TextInverse     = ColorTranslator.FromHtml("#080C14");

        // ── Borders ────────────────────────────────────────────────────
        public static readonly Color BorderSubtle    = ColorTranslator.FromHtml("#1A2D48");
        public static readonly Color BorderDefault   = ColorTranslator.FromHtml("#213A58");
        public static readonly Color BorderMid       = ColorTranslator.FromHtml("#2A4A70");
        public static readonly Color BorderAccentBlue = ColorTranslator.FromHtml("#1E6ABF");
        public static readonly Color BorderAccentRed  = ColorTranslator.FromHtml("#8B2030");

        // ── Status / Semantic ──────────────────────────────────────────
        public static readonly Color StatusSuccess   = ColorTranslator.FromHtml("#22C55E");
        public static readonly Color StatusSuccessBg = ColorTranslator.FromHtml("#0A2818");
        public static readonly Color StatusSuccessBd = ColorTranslator.FromHtml("#1A5030");

        public static readonly Color StatusWarn      = ColorTranslator.FromHtml("#E8A020");
        public static readonly Color StatusWarnBg    = ColorTranslator.FromHtml("#1E1800");
        public static readonly Color StatusWarnBd    = ColorTranslator.FromHtml("#6A4800");

        public static readonly Color StatusError     = ColorTranslator.FromHtml("#C84040");
        public static readonly Color StatusErrorBg   = ColorTranslator.FromHtml("#200A0A");
        public static readonly Color StatusErrorBd   = ColorTranslator.FromHtml("#6A1818");

        public static readonly Color StatusInfo      = ColorTranslator.FromHtml("#2E8BFF");
        public static readonly Color StatusInfoBg    = ColorTranslator.FromHtml("#091828");
        public static readonly Color StatusInfoBd    = ColorTranslator.FromHtml("#1A3A6A");

        // ── Console Output Colors (Milestone 3) ────────────────────────
        public static readonly Color ConsoleBg      = ColorTranslator.FromHtml("#060E1A");
        public static readonly Color LogInfo        = ColorTranslator.FromHtml("#4AB4FF");
        public static readonly Color LogSuccess     = ColorTranslator.FromHtml("#22C55E");
        public static readonly Color LogWarn        = ColorTranslator.FromHtml("#E8A020");
        public static readonly Color LogError       = ColorTranslator.FromHtml("#FF4444");
        public static readonly Color LogDebug       = ColorTranslator.FromHtml("#C084FC");
        public static readonly Color LogDefault     = Color.White;
        public static readonly Color LogMeta        = ColorTranslator.FromHtml("#607090");
    }
}

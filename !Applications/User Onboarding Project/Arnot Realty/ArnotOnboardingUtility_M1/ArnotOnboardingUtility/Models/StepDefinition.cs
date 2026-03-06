// =============================================================
// ArnotOnboardingUtility — Models/StepDefinition.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Describes a single step in the engineer workflow.
//              StepCatalog returns the ordered list of these
//              for the current user type.
// =============================================================
using System;

namespace ArnotOnboardingUtility.Models
{
    /// <summary>How a step is executed by the engineer.</summary>
    public enum StepType
    {
        /// <summary>PowerShell script runs via ScriptManager. Mark Complete requires successful run.</summary>
        Automated,
        /// <summary>Guidance card only. Mark Complete always available once step is active.</summary>
        Manual,
        /// <summary>Guidance + optional script. Mark Complete always available.</summary>
        Hybrid
    }

    /// <summary>
    /// Immutable description of one step in the onboarding workflow.
    /// Produced by StepCatalog. Instantiated once per session load.
    /// </summary>
    public class StepDefinition
    {
        /// <summary>Zero-based position in the resolved step list for this session.</summary>
        public int Index { get; set; }

        /// <summary>Step label, e.g. "1", "1a", "3b".</summary>
        public string StepLabel { get; set; } = "";

        /// <summary>Human-readable title shown in the card header.</summary>
        public string Title { get; set; } = "";

        /// <summary>Automated / Manual / Hybrid execution model.</summary>
        public StepType Type { get; set; } = StepType.Manual;

        /// <summary>
        /// Structured guidance text rendered in the card body.
        /// May contain {PlaceholderKeys} resolved from OnboardingRecord at render time.
        /// </summary>
        public string GuidanceText { get; set; } = "";

        /// <summary>
        /// Embedded .ps1 resource name (e.g. "New-ArnotADUser.ps1").
        /// Null for Manual steps.
        /// </summary>
        public string ScriptResourceName { get; set; }

        /// <summary>
        /// Factory delegate that extracts parameters from the record
        /// and passes them to ScriptManager. Null for Manual steps.
        /// Set in StepCatalog per-step. Wired in Milestone 3/4/5.
        /// </summary>
        public Func<OnboardingRecord, System.Collections.Generic.Dictionary<string, object>> ParameterFactory { get; set; }

        /// <summary>Phase grouping for display headers.</summary>
        public string Phase { get; set; } = "Account Setup";

        /// <summary>
        /// Whether this step was included in the current session
        /// (false = conditional step hidden because its flag was false).
        /// </summary>
        public bool IsVisible { get; set; } = true;

        // ── Display Helpers ───────────────────────────────────────────

        public string TypeLabel =>
            Type == StepType.Automated ? "Automated" :
            Type == StepType.Hybrid    ? "Hybrid"    : "Manual";

        public bool HasScript => !string.IsNullOrEmpty(ScriptResourceName);
    }
}

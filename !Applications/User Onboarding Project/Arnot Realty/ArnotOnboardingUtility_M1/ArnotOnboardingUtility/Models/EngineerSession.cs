// =============================================================
// ArnotOnboardingUtility — Models/EngineerSession.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Progress state for a single onboarding workflow
//              session. Persisted to AppData as JSON. One file
//              per recordId. Survives application restart.
// =============================================================
using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace ArnotOnboardingUtility.Models
{
    public class EngineerSession
    {
        // ── Identity ──────────────────────────────────────────────────
        [JsonProperty("recordId")]
        public string RecordId { get; set; } = "";

        [JsonProperty("employeeName")]
        public string EmployeeName { get; set; } = "";

        [JsonProperty("userType")]
        public string UserType { get; set; } = "Desktop"; // "Desktop" | "Kiosk"

        [JsonProperty("jsonSourcePath")]
        public string JsonSourcePath { get; set; } = "";

        // ── Progress ──────────────────────────────────────────────────
        [JsonProperty("totalSteps")]
        public int TotalSteps { get; set; }

        [JsonProperty("currentStepIndex")]
        public int CurrentStepIndex { get; set; }

        [JsonProperty("completedSteps")]
        public List<int> CompletedSteps { get; set; } = new List<int>();

        [JsonProperty("stepNotes")]
        public Dictionary<string, string> StepNotes { get; set; } = new Dictionary<string, string>();

        // ── Log File ──────────────────────────────────────────────────
        [JsonProperty("sessionLogPath")]
        public string SessionLogPath { get; set; } = "";

        // ── Timestamps ────────────────────────────────────────────────
        [JsonProperty("startedAt")]
        public DateTime StartedAt { get; set; }

        [JsonProperty("lastWorked")]
        public DateTime LastWorked { get; set; }

        // ── Computed Helpers ──────────────────────────────────────────

        [JsonIgnore]
        public bool IsComplete => CompletedSteps.Count >= TotalSteps && TotalSteps > 0;

        [JsonIgnore]
        public bool IsKiosk => UserType == "Kiosk";

        public bool StepIsComplete(int index) => CompletedSteps.Contains(index);

        public void MarkStepComplete(int index)
        {
            if (!CompletedSteps.Contains(index))
                CompletedSteps.Add(index);
            if (CurrentStepIndex == index)
                CurrentStepIndex = index + 1;
            LastWorked = DateTime.Now;
        }

        public void SetNote(string stepKey, string note)
        {
            StepNotes[stepKey] = note;
            LastWorked = DateTime.Now;
        }

        public string GetNote(string stepKey)
        {
            return StepNotes.TryGetValue(stepKey, out var note) ? note : "";
        }

        /// <summary>Progress text for display in landing view.</summary>
        [JsonIgnore]
        public string ProgressDisplay =>
            TotalSteps > 0
                ? $"Step {Math.Min(CurrentStepIndex + 1, TotalSteps)} of {TotalSteps}"
                : "Not started";
    }
}

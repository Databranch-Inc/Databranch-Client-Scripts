// =============================================================
// ArnotOnboarding — RequestorProfile.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: The saved profile of the person submitting onboarding
//              requests (the "My Information" view). Pre-fills page 4
//              of the wizard. One profile per %AppData% installation —
//              since each user has their own AppData, this is inherently
//              per-user without needing an account system.
// =============================================================

namespace ArnotOnboarding.Models
{
    public class RequestorProfile
    {
        public string SchemaVersion { get; set; } = "1.0";
        public string Name          { get; set; } = string.Empty;
        public string Title         { get; set; } = string.Empty;
        public string Phone         { get; set; } = string.Empty;
        public string Email         { get; set; } = string.Empty;
        public string Department    { get; set; } = string.Empty;
    }
}

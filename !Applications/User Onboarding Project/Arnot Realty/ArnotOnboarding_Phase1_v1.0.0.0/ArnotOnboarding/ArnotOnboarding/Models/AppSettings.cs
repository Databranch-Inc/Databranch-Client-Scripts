// =============================================================
// ArnotOnboarding — AppSettings.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Application-level settings persisted to %AppData%.
// =============================================================

using System.Drawing;

namespace ArnotOnboarding.Models
{
    public class AppSettings
    {
        public string SchemaVersion     { get; set; } = "1.0";

        // Window state
        public int    WindowX           { get; set; } = 100;
        public int    WindowY           { get; set; } = 100;
        public int    WindowWidth       { get; set; } = 1100;
        public int    WindowHeight      { get; set; } = 760;
        public bool   WindowMaximized   { get; set; } = false;

        // Auto-save
        public int    AutoSaveDebounceMs { get; set; } = 750;

        // Draft export/import
        public string LastDraftExportDirectory { get; set; } = string.Empty;
        public string LastDraftImportDirectory { get; set; } = string.Empty;

        // Record library
        public string LastViewedRecordId { get; set; } = string.Empty;
    }
}

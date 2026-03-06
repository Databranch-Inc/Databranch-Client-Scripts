// =============================================================
// ArnotOnboarding — AppSettings.cs
// Version    : 1.5.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Modified   : 2026-02-27
// Description: Application-level settings persisted to %AppData%.
//              Now includes HR export path configuration split into
//              two editable segments with a computed full path.
// =============================================================

using System.IO;

namespace ArnotOnboarding.Models
{
    public class AppSettings
    {
        public string SchemaVersion { get; set; } = "1.0";

        // ── Window state ──────────────────────────────────────────────
        public int  WindowX        { get; set; } = 100;
        public int  WindowY        { get; set; } = 100;
        public int  WindowWidth    { get; set; } = 1100;
        public int  WindowHeight   { get; set; } = 760;
        public bool WindowMaximized { get; set; } = false;

        // ── Auto-save ─────────────────────────────────────────────────
        public int AutoSaveDebounceMs { get; set; } = 750;

        // ── Draft export/import ───────────────────────────────────────
        public string LastDraftExportDirectory { get; set; } = string.Empty;
        public string LastDraftImportDirectory { get; set; } = string.Empty;

        // ── Record library ────────────────────────────────────────────
        public string LastViewedRecordId { get; set; } = string.Empty;

        // ── HR Export Path — two editable segments ────────────────────
        //
        // Full path structure:
        //   {HrBasePath}\{LastName, FirstName}\{HrSubPath}\
        //
        // Example (production):
        //   R:\66 Human Resources Q\666 Employee Files\
        //   Doe, Jane
        //   \01 Employment\01 Hiring\04 Onboarding
        //
        // Example (dev/testing override):
        //   C:\Temp\HRTest\
        //   Doe, Jane
        //   \01 Employment\01 Hiring\04 Onboarding

        /// <summary>
        /// Root of the HR file share, before the "LastName, FirstName" segment.
        /// Default: R:\66 Human Resources Q\666 Employee Files
        /// </summary>
        public string HrBasePath { get; set; } =
            @"R:\66 Human Resources Q\666 Employee Files";

        /// <summary>
        /// Sub-path appended after the "LastName, FirstName" folder.
        /// Default: \01 Employment\01 Hiring\04 Onboarding
        /// </summary>
        public string HrSubPath { get; set; } =
            @"01 Employment\01 Hiring\04 Onboarding";

        // ── Notification email recipients ─────────────────────────────
        public string NotifyEmail1 { get; set; } = "support@databranch.com";
        public string NotifyEmail2 { get; set; } = "help@databranch.com";

        // ── Computed helper ───────────────────────────────────────────

        /// <summary>
        /// Builds the full export directory for a specific employee.
        /// Format: {HrBasePath}\{lastName, firstName}\{HrSubPath}
        /// </summary>
        public string BuildEmployeeExportPath(string lastName, string firstName)
        {
            string dirName = $"{lastName.Trim()}, {firstName.Trim()}";
            string sub     = HrSubPath.TrimStart('\\').TrimStart('/');
            return Path.Combine(HrBasePath, dirName, sub);
        }

        /// <summary>
        /// Returns the "LastName, FirstName" root directory for an employee
        /// (one level above HrSubPath). Used for the network requery scan.
        /// </summary>
        public string BuildEmployeeRootPath(string lastName, string firstName)
        {
            string dirName = $"{lastName.Trim()}, {firstName.Trim()}";
            return Path.Combine(HrBasePath, dirName);
        }
    }
}

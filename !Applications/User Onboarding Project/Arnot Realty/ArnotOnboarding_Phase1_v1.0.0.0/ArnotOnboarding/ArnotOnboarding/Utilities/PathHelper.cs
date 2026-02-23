// =============================================================
// ArnotOnboarding — PathHelper.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Utility helpers for file path generation, validation,
//              and safe filename construction.
// =============================================================

using System;
using System.IO;
using System.Text.RegularExpressions;
using ArnotOnboarding.Models;

namespace ArnotOnboarding.Utilities
{
    public static class PathHelper
    {
        // ── Safe Filename Construction ──────────────────────────────

        /// <summary>
        /// Strips characters that are invalid in Windows file/folder names.
        /// Replaces spaces with underscores.
        /// </summary>
        public static string MakeSafe(string input)
        {
            if (string.IsNullOrWhiteSpace(input))
                return "Unknown";

            // Remove all invalid path characters
            string invalid = new string(Path.GetInvalidFileNameChars()) +
                             new string(Path.GetInvalidPathChars());
            string pattern = $"[{Regex.Escape(invalid)}]";
            string safe    = Regex.Replace(input, pattern, "");

            return safe.Trim().Replace(" ", "_");
        }

        // ── Export Folder Naming ────────────────────────────────────

        /// <summary>
        /// Builds the suggested export folder name for a given record.
        /// Format: {YYYY-MM-DD}_{LastName}_{FirstName}
        /// </summary>
        public static string BuildExportFolderName(OnboardingRecord record)
        {
            string date  = record.FinalizedAt?.ToString("yyyy-MM-dd")
                        ?? DateTime.Now.ToString("yyyy-MM-dd");
            string last  = MakeSafe(record.EmployeeLastName);
            string first = MakeSafe(record.EmployeeFirstName);

            return $"{date}_{last}_{first}";
        }

        /// <summary>
        /// Builds the base file name (without extension) for the PDF and JSON exports.
        /// Format: {LastName}_{FirstName}_Onboarding
        /// </summary>
        public static string BuildExportFileName(OnboardingRecord record)
        {
            string last  = MakeSafe(record.EmployeeLastName);
            string first = MakeSafe(record.EmployeeFirstName);
            return $"{last}_{first}_Onboarding";
        }

        // ── Lock File Paths ─────────────────────────────────────────

        /// <summary>Returns the expected .lock file path for a given JSON export path.</summary>
        public static string GetLockFilePath(string jsonExportPath)
            => jsonExportPath + ".lock";

        // ── Validation ──────────────────────────────────────────────

        /// <summary>
        /// Attempts to verify that a directory path is accessible (exists and can be written to).
        /// Returns true if accessible; false otherwise.
        /// </summary>
        public static bool IsDirectoryAccessible(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
                return false;

            // Try creating a temp file to verify write access
            string testFile = Path.Combine(path, $"_write_test_{Guid.NewGuid()}.tmp");
            try
            {
                File.WriteAllText(testFile, "test");
                File.Delete(testFile);
                return true;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Returns a user-friendly description of a path for display in the UI.
        /// Truncates long UNC paths by showing the last 2-3 segments.
        /// </summary>
        public static string GetDisplayPath(string fullPath, int maxLength = 60)
        {
            if (string.IsNullOrWhiteSpace(fullPath)) return "(not set)";
            if (fullPath.Length <= maxLength) return fullPath;

            // Show the last portion of a long path with "..." prefix
            string trimmed = "..." + fullPath.Substring(fullPath.Length - (maxLength - 3));
            int nextSep = trimmed.IndexOf(Path.DirectorySeparatorChar, 4);
            return nextSep > 0 ? "..." + trimmed.Substring(nextSep) : trimmed;
        }
    }
}
